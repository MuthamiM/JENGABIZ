import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/stock_image_cache_service.dart';
import 'shimmer.dart';

class CachedStockImage extends StatefulWidget {
  const CachedStockImage({
    super.key,
    required this.imageUrl,
    required this.ownerId,
    this.width = 70,
    this.height = 70,
  });

  final String imageUrl;
  final String? ownerId;
  final double width;
  final double height;

  @override
  State<CachedStockImage> createState() => _CachedStockImageState();
}

class _CachedStockImageState extends State<CachedStockImage> {
  static final Map<String, DateTime> _recentFailureByKey = {};
  static const Duration _retryCooldown = Duration(seconds: 20);

  File? _cachedFile;
  Uint8List? _memoryBytes;
  int _loadGeneration = 0;
  bool _finishedInitialLoad = false;

  @override
  void initState() {
    super.initState();
    _primeMemory();
    JengaApiService.instance.isOnline.addListener(_onConnectivityChanged);
    StockImageCacheService.instance.revision.addListener(_onCacheUpdated);
    _loadLocalOrRemoteImage();
  }

  @override
  void didUpdateWidget(covariant CachedStockImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.ownerId != widget.ownerId) {
      _cachedFile = null;
      _memoryBytes = null;
      _finishedInitialLoad = false;
      _primeMemory();
      _loadLocalOrRemoteImage();
    }
  }

  @override
  void dispose() {
    JengaApiService.instance.isOnline.removeListener(_onConnectivityChanged);
    StockImageCacheService.instance.revision.removeListener(_onCacheUpdated);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (JengaApiService.instance.isOnline.value &&
        _cachedFile == null &&
        _memoryBytes == null) {
      _recentFailureByKey.clear();
      _loadLocalOrRemoteImage();
    }
  }

  void _onCacheUpdated() {
    if (!mounted || _memoryBytes != null || _cachedFile != null) return;
    final key = _cacheItemKey;
    if (key == null) return;
    final ownerId = widget.ownerId ?? '';
    final mem = StockImageCacheService.instance.peekMemory(ownerId, key);
    if (mem != null) {
      setState(() {
        _memoryBytes = mem;
        _finishedInitialLoad = true;
      });
      return;
    }
    _loadLocalOrRemoteImage();
  }

  void _primeMemory() {
    final key = _cacheItemKey;
    if (key == null) return;
    final ownerId = widget.ownerId ?? '';
    _memoryBytes = StockImageCacheService.instance.peekMemory(ownerId, key);
    if (_memoryBytes != null) {
      _finishedInitialLoad = true;
    }
  }

  String? get _stockImageId {
    const prefix = 'stock-image:';
    if (!widget.imageUrl.startsWith(prefix)) return null;
    final id = widget.imageUrl.substring(prefix.length);
    return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ? id : null;
  }

  Uri? get _remoteUri {
    final url = widget.imageUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return null;
    return uri;
  }

  String? get _cacheItemKey =>
      StockImageCacheService.itemKeyForUrl(widget.imageUrl);

  Future<void> _loadLocalOrRemoteImage() async {
    final cacheKey = _cacheItemKey;
    if (cacheKey == null) {
      if (mounted) setState(() => _finishedInitialLoad = true);
      return;
    }
    final ownerId = widget.ownerId ?? '';
    final stockId = _stockImageId;
    final remoteUri = _remoteUri;
    final generation = ++_loadGeneration;

    try {
      final service = StockImageCacheService.instance;

      // 1. Check local storage first (instant offline & online display).
      final localFile = await service.getImage(ownerId, cacheKey);
      if (!mounted || generation != _loadGeneration) return;

      if (localFile != null) {
        final mem = service.peekMemory(ownerId, cacheKey);
        setState(() {
          _cachedFile = localFile;
          if (mem != null) _memoryBytes = mem;
          _finishedInitialLoad = true;
        });

        // If offline or cache was refreshed within the last 6 hours, keep local.
        if (!JengaApiService.instance.isOnline.value) return;
        try {
          final modTime = await localFile.lastModified();
          if (DateTime.now().difference(modTime) < const Duration(hours: 6)) {
            return;
          }
        } catch (_) {
          return;
        }
      }

      // If no authenticated session for stock-image: TeleDrive API, stop at local cache.
      if (stockId != null && JengaApiService.instance.authToken == null) {
        if (mounted && generation == _loadGeneration) {
          setState(() => _finishedInitialLoad = true);
        }
        return;
      }

      // Never trap offline views in shimmer: finish initial load before network probing.
      if (!JengaApiService.instance.isOnline.value &&
          mounted &&
          generation == _loadGeneration) {
        setState(() => _finishedInitialLoad = true);
      }

      final failedAt = _recentFailureByKey[cacheKey];
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < _retryCooldown) {
        if (mounted && generation == _loadGeneration) {
          setState(() => _finishedInitialLoad = true);
        }
        return;
      }

      // 2. Fetch from TeleDrive backend or remote URL when online / recovering.
      final bytes = stockId != null
          ? await JengaApiService.instance.fetchStockImage(stockId)
          : remoteUri != null
              ? await JengaApiService.instance.fetchRemoteImage(remoteUri)
              : null;
      if (!mounted || generation != _loadGeneration) return;

      if (bytes == null || bytes.isEmpty) {
        _recentFailureByKey[cacheKey] = DateTime.now();
        if (mounted && generation == _loadGeneration) {
          setState(() => _finishedInitialLoad = true);
        }
        return;
      }

      _recentFailureByKey.remove(cacheKey);
      setState(() {
        _memoryBytes = bytes;
        _finishedInitialLoad = true;
      });
      try {
        final savedFile = await service.saveImage(ownerId, cacheKey, bytes);
        if (mounted && generation == _loadGeneration) {
          setState(() => _cachedFile = savedFile);
        }
      } catch (_) {
        // Memory bytes are already displayed even if disk persistence failed.
      }
    } catch (_) {
      // Keep local image or cleanly display placeholder.
    } finally {
      if (mounted && generation == _loadGeneration && !_finishedInitialLoad) {
        setState(() => _finishedInitialLoad = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
          width: widget.width,
          height: widget.height,
          color: const Color(0xFFE8EEF8),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined,
              color: Color(0xFF1E6BFF), size: 28),
        );

    final url = widget.imageUrl;
    if (url.startsWith('data:image/')) {
      final comma = url.indexOf(',');
      if (comma < 0) return placeholder();
      try {
        return Image.memory(
          base64Decode(url.substring(comma + 1)),
          width: widget.width,
          height: widget.height,
          cacheWidth: (widget.width * 2).round(),
          cacheHeight: (widget.height * 2).round(),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder(),
        );
      } catch (_) {
        return placeholder();
      }
    }
    if (_cacheItemKey != null) {
      final memBytes = _memoryBytes;
      if (memBytes != null) {
        return Image.memory(
          memBytes,
          width: widget.width,
          height: widget.height,
          cacheWidth: (widget.width * 2).round(),
          cacheHeight: (widget.height * 2).round(),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => placeholder(),
        );
      }
      final file = _cachedFile;
      if (file != null) {
        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          cacheWidth: (widget.width * 2).round(),
          cacheHeight: (widget.height * 2).round(),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => placeholder(),
        );
      }
      if (_finishedInitialLoad) return placeholder();
      return ShimmerBox(
        width: widget.width,
        height: widget.height,
        borderRadius: 12,
      );
    }
    return placeholder();
  }
}
