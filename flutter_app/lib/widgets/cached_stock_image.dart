import 'dart:convert';
import 'dart:io';

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
  File? _cachedFile;
  int _loadGeneration = 0;
  bool _finishedInitialLoad = false;

  @override
  void initState() {
    super.initState();
    _loadRemoteImage();
  }

  @override
  void didUpdateWidget(covariant CachedStockImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.ownerId != widget.ownerId) {
      _cachedFile = null;
      _finishedInitialLoad = false;
      _loadRemoteImage();
    }
  }

  String? get _itemId {
    const prefix = 'stock-image:';
    if (!widget.imageUrl.startsWith(prefix)) return null;
    final id = widget.imageUrl.substring(prefix.length);
    return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ? id : null;
  }

  Future<void> _loadRemoteImage() async {
    final ownerId = widget.ownerId;
    final itemId = _itemId;
    if (ownerId == null || itemId == null) return;
    final generation = ++_loadGeneration;
    try {
      final service = StockImageCacheService.instance;
      final file = await service.getImage(ownerId, itemId);
      if (!mounted || generation != _loadGeneration) return;
      if (file != null) setState(() => _cachedFile = file);

      final isFresh = file != null &&
          DateTime.now().difference(await file.lastModified()) <
              const Duration(hours: 6);
      if (isFresh) return;

      final bytes = await JengaApiService.instance.fetchStockImage(itemId);
      if (bytes == null ||
          bytes.isEmpty ||
          !mounted ||
          generation != _loadGeneration) {
        return;
      }
      final saved = await service.saveImage(ownerId, itemId, bytes);
      if (mounted && generation == _loadGeneration) {
        setState(() => _cachedFile = saved);
      }
    } catch (_) {
      // Keep an existing cached photo available when the shop is offline.
    } finally {
      if (mounted && generation == _loadGeneration) {
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
    if (url.startsWith('stock-image:')) {
      if (widget.ownerId == null) return placeholder();
      final file = _cachedFile;
      if (file != null) {
        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          cacheWidth: (widget.width * 2).round(),
          cacheHeight: (widget.height * 2).round(),
          fit: BoxFit.cover,
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
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        width: widget.width,
        height: widget.height,
        cacheWidth: (widget.width * 2).round(),
        cacheHeight: (widget.height * 2).round(),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : ShimmerBox(
                width: widget.width,
                height: widget.height,
                borderRadius: 12,
              ),
      );
    }
    return placeholder();
  }
}
