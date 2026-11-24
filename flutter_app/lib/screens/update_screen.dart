import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_update_service.dart';

const _updateBlue = Color(0xFF1E6BFF);
const _updateInk = Color(0xFF17162A);
const _updateBg = Color(0xFFF8F8FF);
const _updateMuted = Color(0xFF777487);
const _updateTint = Color(0xFFE8F1FF);
const _updateLine = Color(0xFFE4E6F0);

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({
    super.key,
    required this.onBack,
    this.initialRelease,
  });

  final ValueChanged<JengaBizRelease?> onBack;
  final JengaBizRelease? initialRelease;

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen>
    with WidgetsBindingObserver {
  String _installedVersion = 'Checking…';
  String? _latestVersion;
  JengaBizRelease? _release;
  String? _apkPath;
  String? _error;
  double? _downloadProgress;
  bool _checking = true;
  bool _canInstall = false;
  bool _installing = false;
  bool _showAllReleaseNotes = false;

  bool get _isDownloading => _downloadProgress != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshInstallPermission());
    }
  }

  Future<void> _refreshInstallPermission() async {
    final canInstall = await AppUpdateService.instance.canInstallPackages();
    if (mounted) setState(() => _canInstall = canInstall);
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _checking = true;
        _error = null;
      });
    }
    try {
      final latestRelease = widget.initialRelease == null
          ? AppUpdateService.instance.latestRelease()
          : Future<JengaBizRelease?>.value(widget.initialRelease);
      final results = await Future.wait<Object?>([
        AppUpdateService.instance.installedAppInfo(),
        latestRelease,
        AppUpdateService.instance.canInstallPackages(),
      ]);
      final info = results[0] as Map<String, dynamic>;
      final latest = (results[1] as JengaBizRelease?) ?? widget.initialRelease;
      final canInstall = results[2] as bool;
      final currentVersionCode = _asInt(info['versionCode']);
      final currentVersion = info['versionName']?.toString() ?? 'Unknown';
      if (!mounted) return;
      setState(() {
        _installedVersion = currentVersion;
        _latestVersion = latest?.versionName;
        _release = latest != null &&
                (currentVersionCode == null ||
                    latest.versionCode > currentVersionCode)
            ? latest
            : null;
        _canInstall = canInstall;
        _checking = false;
        _showAllReleaseNotes = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _release = widget.initialRelease;
        _latestVersion = widget.initialRelease?.versionName;
        _checking = false;
        _error =
            'Could not check for updates. Connect to the internet and try again.';
      });
    }
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _allowInstall() async {
    setState(() => _error = null);
    try {
      await AppUpdateService.instance.openInstallSettings();
    } on Object {
      if (mounted) {
        setState(() => _error = 'Android could not open the install setting.');
      }
    }
  }

  Future<void> _installUpdate() async {
    final release = _release;
    if (release == null || _isDownloading || _installing) return;
    setState(() => _error = null);

    if (!_canInstall) {
      await _allowInstall();
      return;
    }

    try {
      var apkPath = _apkPath;
      if (apkPath == null) {
        setState(() => _downloadProgress = 0);
        apkPath = await AppUpdateService.instance.downloadAndVerify(
          release,
          onProgress: (progress) {
            if (mounted) setState(() => _downloadProgress = progress);
          },
        );
        if (!mounted) return;
        setState(() {
          _apkPath = apkPath;
          _downloadProgress = null;
        });
      }
      setState(() => _installing = true);
      await AppUpdateService.instance.installApk(apkPath);
    } on AppUpdateException catch (error) {
      if (mounted) {
        setState(() {
          _downloadProgress = null;
          _installing = false;
          _error = error.message;
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = error.code == 'install_permission_required'
              ? 'Allow JengaBiz to install updates in Android settings, then tap Install update.'
              : 'Android could not open the installer. Please try again.';
        });
      }
      await _refreshInstallPermission();
    } on Object {
      if (mounted) {
        setState(() {
          _installing = false;
          _downloadProgress = null;
          _error = 'Could not start the update. Please try again.';
        });
      }
    }
  }

  String get _primaryLabel {
    if (_checking) return 'Checking for updates';
    if (_isDownloading) return 'Downloading update';
    if (_installing) return 'Opening installer';
    if (_release != null && !_canInstall) return 'Allow app installs';
    if (_apkPath != null) return 'Install update';
    if (_release != null) return 'Update now';
    return 'Check again';
  }

  Future<void> _onPrimaryPressed() async {
    if (_checking || _isDownloading || _installing) return;
    if (_release == null) {
      await _refresh();
    } else {
      await _installUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    return Scaffold(
      backgroundColor: _updateBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/jengabiz_mark.png',
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        'JengaBiz',
                        style: TextStyle(
                          color: _updateInk,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Not now',
                        onPressed: () => widget.onBack(_release),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Center(
                    child: Container(
                      width: 142,
                      height: 142,
                      decoration: const BoxDecoration(
                        color: _updateTint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        size: 66,
                        color: _updateBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Text(
                    release == null ? 'App updates' : 'Update JengaBiz',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _updateInk,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _checking
                        ? 'Checking the latest version…'
                        : release == null
                            ? 'You’re using the latest version.'
                            : 'Version ${release.versionName} is ready to install.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _updateMuted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _versionRow(release),
                  if (release != null && release.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const Text(
                      'What’s new',
                      style: TextStyle(
                        color: _updateInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 9),
                    ...(_showAllReleaseNotes || release.releaseNotes.length <= 3
                            ? release.releaseNotes
                            : release.releaseNotes.take(3))
                        .map(_noteRow),
                    if (release.releaseNotes.length > 3)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() =>
                              _showAllReleaseNotes = !_showAllReleaseNotes),
                          style: TextButton.styleFrom(
                            foregroundColor: _updateBlue,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            _showAllReleaseNotes ? 'Less' : 'More…',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (_isDownloading) ...[
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(9),
                      color: _updateBlue,
                      backgroundColor: _updateTint,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _downloadProgress == null
                          ? 'Preparing secure download…'
                          : '${(_downloadProgress! * 100).round()}% downloaded',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _updateMuted, fontSize: 12),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB42335),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _checking || _isDownloading || _installing
                          ? null
                          : _onPrimaryPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: _updateBlue,
                        disabledBackgroundColor: _updateBlue.withOpacity(.45),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isDownloading || _installing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _primaryLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                  if (release != null) ...[
                    const SizedBox(height: 7),
                    TextButton(
                      onPressed: () => widget.onBack(release),
                      child: const Text(
                        'Not now',
                        style: TextStyle(color: _updateMuted),
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  const Text(
                    'The download is checksum-verified before Android opens its installer. Android will ask you to confirm the installation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _updateMuted,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _versionRow(JengaBizRelease? release) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _updateLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _versionColumn('INSTALLED', _installedVersion)),
          const Icon(Icons.arrow_forward_rounded, color: _updateBlue, size: 19),
          Expanded(
            child: _versionColumn(
              'LATEST',
              release?.versionName ?? _latestVersion ?? _installedVersion,
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _versionColumn(String label, String version, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _updateMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          version,
          style: const TextStyle(
            color: _updateInk,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _noteRow(String note) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.check_circle_rounded,
                  size: 16, color: _updateBlue),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                note,
                style: const TextStyle(
                  color: _updateMuted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
}
