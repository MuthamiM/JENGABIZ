import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'legal_documents.dart';
import 'screens/auth_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/update_screen.dart';
import 'services/app_update_service.dart';
import 'services/api_service.dart';
import 'services/db_service.dart';
import 'services/firebase_push_service.dart';
import 'services/inventory_pdf_export_service.dart';
import 'services/location_biometric_service.dart';
import 'services/stock_notification_service.dart';

const kBlue = Color(0xFF1E6BFF);
const kPurple = kBlue;
const kInk = Color(0xFF17162A);
const kBg = Color(0xFFF8F8FF);
const kMuted = Color(0xFF777487);
const kTintPurple = Color(0xFFE8F1FF);
const kTintMint = Color(0xFFE1F6F4);
const kTintPeach = Color(0xFFFFF0DC);
const kTintBlue = Color(0xFFE2EFFB);
const kShadow = Color(0x14373159);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JengaBizApp());
  unawaited(FirebasePushService.instance.prepareBackgroundHandling());
}

class JengaBizApp extends StatelessWidget {
  const JengaBizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JengaBiz',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBlue,
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.manropeTextTheme()
            .apply(bodyColor: kInk, displayColor: kInk),
      ),
      home: const Root(),
    );
  }
}

typedef DukaLedgerApp = JengaBizApp;

enum AppScreen {
  splash,
  welcome,
  auth,
  home,
  analytics,
  profile,
  notifications,
  stock,
  update,
}

class Notice {
  Notice(this.id, this.title, this.body, this.time, this.tone, this.icon,
      {this.read = false});
  final int id;
  final String title, body, time;
  final Color tone;
  final IconData icon;
  bool read;
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> with WidgetsBindingObserver {
  late AppScreen screen;
  Timer? _stockRetryTimer;
  JengaBizRelease? _availableUpdate;
  AppScreen _screenBeforeUpdate = AppScreen.splash;
  bool _hasSeenWelcome = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    screen = AppScreen.splash;
    unawaited(_initializeApp());
    _initAppLocation();
    _startPendingStockRetries();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPendingStockRetries();
      unawaited(_syncAccountInventoryOnResume());
      unawaited(_retryPendingStockUpload());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stockRetryTimer?.cancel();
      _stockRetryTimer = null;
    }
  }

  void _startPendingStockRetries() {
    _stockRetryTimer?.cancel();
    _stockRetryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_retryPendingStockUpload()),
    );
  }

  Future<void> _retryPendingStockUpload() async {
    try {
      if (await JengaDB.instance.hasPendingStockSync()) {
        await JengaDB.instance.syncStockWithServer();
      }
    } catch (_) {
      // The retry timer will try again when connectivity returns.
    }
  }

  Future<void> _syncAccountInventoryOnResume() async {
    try {
      if (JengaApiService.instance.authToken != null) {
        await JengaDB.instance.syncStockWithServer();
      }
    } catch (_) {
      // A failed pull leaves the account's local inventory available offline.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stockRetryTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      await JengaDB.instance.init();
      if (JengaApiService.instance.authToken != null) {
        unawaited(_initializePushNotifications());
      }
    } catch (_) {}

    final hasExistingAccount = JengaDB.instance.shouldResumeSavedSession ||
        JengaDB.instance.currentUser != null ||
        JengaDB.instance.users.isNotEmpty;
    var welcomeSeen = hasExistingAccount;
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedWelcomeSeen = preferences.getBool(_welcomeSeenKey);
      if (savedWelcomeSeen != null) {
        welcomeSeen = savedWelcomeSeen;
      } else if (hasExistingAccount) {
        await preferences.setBool(_welcomeSeenKey, true);
      }
    } catch (_) {}

    _hasSeenWelcome = welcomeSeen;
    final initialScreen = JengaDB.instance.shouldResumeSavedSession
        ? AppScreen.home
        : welcomeSeen
            ? AppScreen.auth
            : AppScreen.welcome;
    if (!mounted) return;
    _screenBeforeUpdate = initialScreen;
    setState(() => screen = initialScreen);
    unawaited(_loadAvailableUpdate());
  }

  static const _welcomeSeenKey = 'jengabiz_welcome_seen_v1';

  Future<void> _initializePushNotifications() async {
    try {
      await FirebasePushService.instance.initialize();
    } catch (_) {}
  }

  Future<void> _markWelcomeSeen() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_welcomeSeenKey, true);
    } catch (_) {}
  }

  Future<void> _loadAvailableUpdate() async {
    final update = await AppUpdateService.instance.availableRelease();
    if (!mounted || update == null) return;
    var dismissedUpdateCode = 0;
    try {
      dismissedUpdateCode = (await SharedPreferences.getInstance())
              .getInt('jengabiz_update_dismissed_code') ??
          0;
    } catch (_) {}
    if (update.versionCode > dismissedUpdateCode) {
      setState(() => _availableUpdate = update);
    }
  }

  void _openAppUpdates() {
    _screenBeforeUpdate = screen;
    go(AppScreen.update);
  }

  void _dismissAppUpdate(JengaBizRelease? release) {
    if (release != null) {
      unawaited(SharedPreferences.getInstance().then(
        (preferences) => preferences.setInt(
          'jengabiz_update_dismissed_code',
          release.versionCode,
        ),
      ));
    }
    go(_screenBeforeUpdate);
  }

  void _openAuth() {
    _hasSeenWelcome = true;
    unawaited(_markWelcomeSeen());
    go(JengaDB.instance.shouldResumeSavedSession
        ? AppScreen.home
        : AppScreen.auth);
  }

  void _backFromAuth() {
    if (_hasSeenWelcome) {
      unawaited(SystemNavigator.pop());
    } else {
      go(AppScreen.welcome);
    }
  }

  void _initAppLocation() async {
    try {
      final pos = await LocationBiometricService.instance.getPreciseLocation();
      if (pos != null) {
        JengaDB.instance.latitude = pos.latitude;
        JengaDB.instance.longitude = pos.longitude;
        final hub = LocationBiometricService.instance
            .findNearestHub(pos.latitude, pos.longitude);
        final dist = LocationBiometricService.instance.calculateDistanceKm(
          pos.latitude,
          pos.longitude,
          hub.latitude,
          hub.longitude,
        );
        JengaDB.instance.nearestHubName = hub.name;
        JengaDB.instance.nearestHubDistanceKm = dist;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  final List<Notice> notices = [
    Notice(
        1,
        'New order received',
        'Wireless Headphone x2 was ordered for KES 501.50.',
        '2m ago',
        kTintPurple,
        Icons.shopping_bag_outlined),
    Notice(
        2,
        'Payment received',
        'KES 1,240.00 has been added to your earnings.',
        '1h ago',
        kTintMint,
        Icons.download_rounded),
    Notice(3, 'Low stock alert', 'Running Shoes is down to 12 units.', '3h ago',
        kTintPeach, Icons.inventory_2_outlined),
    Notice(
        4,
        'Delivery completed',
        'Order #13620 was delivered to the customer.',
        'Yesterday',
        kTintBlue,
        Icons.local_shipping_outlined,
        read: true),
    Notice(
        5,
        'Monthly report ready',
        'Your July 2024 report is ready to export.',
        '2 days ago',
        kTintPurple,
        Icons.bar_chart_rounded,
        read: true),
  ];

  int get unread {
    final halfSoldCount =
        JengaDB.instance.items.where((i) => i.isHalfSold).length;
    final noticeCount = notices.where((n) => !n.read).length;
    return halfSoldCount > 0 ? (noticeCount + 3) : noticeCount;
  }

  void go(AppScreen s) => setState(() => screen = s);

  Widget _body() {
    switch (screen) {
      case AppScreen.splash:
        return const AppSplashScreen();
      case AppScreen.welcome:
        return WelcomeScreen(onStart: _openAuth);
      case AppScreen.auth:
        return AuthScreen(
          onSuccess: () => go(AppScreen.home),
          onBack: _backFromAuth,
        );
      case AppScreen.stock:
        return StockScreen(
          onBack: () => go(AppScreen.home),
        );
      case AppScreen.home:
        return HomeScreen(go: go, unread: unread);
      case AppScreen.analytics:
        return AnalyticsScreen(go: go, unread: unread);
      case AppScreen.profile:
        return ProfileScreen(
            go: go,
            unread: unread,
            onCheckForUpdates: _openAppUpdates,
            onSignInAgain: _handleRejectedSession,
            onLogout: () async {
              await JengaDB.instance.logout();
              if (mounted) go(AppScreen.auth);
            });
      case AppScreen.update:
        return UpdateScreen(
          initialRelease: _availableUpdate,
          onBack: _dismissAppUpdate,
        );
      case AppScreen.notifications:
        return NotificationsScreen(
          onBack: () => go(AppScreen.home),
          onNavigate: (route) {
            if (route == 'stock') {
              go(AppScreen.stock);
            } else if (route == 'analytics') {
              go(AppScreen.analytics);
            } else if (route == 'profile') {
              go(AppScreen.profile);
            } else {
              go(AppScreen.home);
            }
          },
        );
    }
  }

  Future<void> _handleRejectedSession() async {
    await JengaDB.instance.clearRejectedSession();
    if (mounted) go(AppScreen.auth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(screen), child: _body()),
        ),
      ),
    );
  }
}

// ---------- Shared widgets ----------

class RoundBtn extends StatelessWidget {
  const RoundBtn(
      {super.key, required this.icon, required this.onTap, this.badge = 0});
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: kShadow, blurRadius: 14, offset: Offset(0, 4))
              ]),
          child: Icon(icon, size: 22, color: const Color(0xFF17162A)),
        ),
        if (badge > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: kPurple,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: kBg, width: 2)),
              child: Text('$badge',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader(
      {super.key, required this.go, required this.unread, this.onBack});
  final void Function(AppScreen) go;
  final int unread;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        onBack != null
            ? RoundBtn(icon: Icons.arrow_back_rounded, onTap: onBack!)
            : GestureDetector(
                onTap: () => go(AppScreen.profile),
                child: const Avatar(size: 46)),
        Row(children: [
          RoundBtn(
              icon: Icons.notifications_none_rounded,
              badge: unread,
              onTap: () => go(AppScreen.notifications)),
          const SizedBox(width: 9),
          RoundBtn(
              icon: Icons.inventory_2_outlined,
              onTap: () => go(AppScreen.stock)),
        ]),
      ]),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.size, this.letter});
  final double size;
  final String? letter;

  @override
  Widget build(BuildContext context) {
    final user = JengaDB.instance.currentUser;
    final initial = letter ??
        (user != null && user.name.trim().isNotEmpty
            ? user.name.trim()[0].toUpperCase()
            : 'J');
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              LinearGradient(colors: [Color(0xFF1E6BFF), Color(0xFF60A5FA)])),
      alignment: Alignment.center,
      child: Container(
        width: size * .54,
        height: size * .54,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(size)),
        alignment: Alignment.center,
        child: Text(initial,
            style: TextStyle(
                fontSize: size * .26,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E6BFF))),
      ),
    );
  }
}

/// Scrollable page with a floating nav that hides while scrolling and
/// returns when scrolling ends.
class NavShell extends StatefulWidget {
  const NavShell(
      {super.key,
      required this.active,
      required this.go,
      required this.children});
  final AppScreen active;
  final void Function(AppScreen) go;
  final List<Widget> children;
  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  bool hidden = false;

  void _set(bool v) {
    if (hidden != v) setState(() => hidden = v);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
            _set(true);
          } else if (n is ScrollEndNotification) {
            _set(false);
          }
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(23, 0, 23, 120),
          children: widget.children,
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 24,
        child: IgnorePointer(
          ignoring: hidden,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            offset: hidden ? const Offset(0, 1.6) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: hidden ? 0 : 1,
              child: Center(
                  child: FloatingNav(active: widget.active, go: widget.go)),
            ),
          ),
        ),
      ),
    ]);
  }
}

class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.active, required this.go});
  final AppScreen active;
  final void Function(AppScreen) go;

  Widget _item(IconData icon, AppScreen s) {
    final on = active == s;
    return GestureDetector(
      onTap: () => go(s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 52,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: on ? const Color(0xFFE8F1FF) : Colors.transparent,
        ),
        child: Icon(icon, color: on ? kBlue : const Color(0xFF747186)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 244,
      height: 65,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: const Color(0xEBFFFFFF),
        borderRadius: BorderRadius.circular(33),
        boxShadow: const [
          BoxShadow(
              color: Color(0x24382F60), blurRadius: 30, offset: Offset(0, 10))
        ],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _item(Icons.home_outlined, AppScreen.home),
        _item(Icons.bar_chart_rounded, AppScreen.analytics),
        _item(Icons.person_outline_rounded, AppScreen.profile),
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text,
      {super.key,
      this.bg = const Color(0xFFC8F1DB),
      this.fg = const Color(0xFF27936A)});
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Text(text,
            style: TextStyle(
                color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

BoxDecoration cardDeco(Color c) {
  return BoxDecoration(
    color: c,
    borderRadius: BorderRadius.circular(20),
    boxShadow: c == Colors.white
        ? const [
            BoxShadow(color: kShadow, blurRadius: 22, offset: Offset(0, 8))
          ]
        : null,
  );
}

class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image(
            image: AssetImage('assets/jengabiz_mark.png'),
            height: 54,
            fit: BoxFit.contain,
          ),
          SizedBox(height: 22),
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: kBlue,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Welcome ----------

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});
  final VoidCallback onStart;

  Widget _feature(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: kTintPurple,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD8E5FF)),
          ),
          child: Icon(icon, color: kBlue, size: 25),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body,
                style:
                    const TextStyle(fontSize: 11, height: 1.6, color: kMuted)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Image.asset(
                        'assets/jengabiz_mark.png',
                        height: 42,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Image.asset('assets/duka-growth-hero.png',
                          height: 250, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 8),
                    const Text('A CLEARER VIEW OF YOUR DUKA',
                        style: TextStyle(
                            color: kBlue,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    const Text('Your shop, stock and sales — all in view.',
                        style: TextStyle(
                            fontSize: 25,
                            height: 1.28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1)),
                    const SizedBox(height: 24),
                    _feature(
                        Icons.inventory_2_outlined,
                        'Know what is in stock',
                        'Keep products, quantities and prices organized in one simple catalog.'),
                    _feature(
                        Icons.notifications_active_outlined,
                        'See what needs attention',
                        'Spot low stock and best sellers so you can make your next move with confidence.'),
                  ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 24, top: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onStart,
              borderRadius: BorderRadius.circular(30),
              child: Ink(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E6BFF), Color(0xFF2563EB)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x401E6BFF),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const SizedBox(width: 44),
                      const Expanded(
                        child: Text(
                          'Explore JengaBiz',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF1E6BFF),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------- Home ----------

class SparklinePainter extends CustomPainter {
  final List<double>? points;
  SparklinePainter({this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    if (points != null && points!.length >= 2) {
      final minVal = points!.reduce(math.min);
      final maxVal = points!.reduce(math.max);
      final diff = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);
      for (int i = 0; i < points!.length; i++) {
        final x = i / (points!.length - 1);
        final y = 1.0 - 0.1 - 0.8 * ((points![i] - minVal) / diff);
        pts.add(Offset(x * size.width, y * size.height));
      }
    } else {
      const defaultPts = [
        Offset(0, .9),
        Offset(.15, .62),
        Offset(.28, .7),
        Offset(.5, .72),
        Offset(.62, .45),
        Offset(.78, .22),
        Offset(.9, .45),
        Offset(1, .05),
      ];
      for (final p in defaultPts) {
        pts.add(Offset(p.dx * size.width, p.dy * size.height));
      }
    }

    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      i == 0
          ? path.moveTo(pts[i].dx, pts[i].dy)
          : path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xCCFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant SparklinePainter oldDelegate) => true;
}

class PiePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const parts = [
      [.68, 0xFF7045E5],
      [.17, 0xFFF2A65E],
      [.13, 0xFFFFD67B],
    ];
    var start = -math.pi / 2;
    for (final p in parts) {
      final sweep = (p[0] as double) * 2 * math.pi;
      canvas.drawArc(
          rect, start, sweep - .03, true, Paint()..color = Color(p[1] as int));
      start += sweep;
    }
    canvas.drawCircle(size.center(Offset.zero), size.width * .17,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.go, required this.unread});
  final void Function(AppScreen) go;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final db = JengaDB.instance;
    final user = db.currentUser;
    final items = db.items;

    // ---- Real KPIs from DB ----
    final totalRevenue =
        items.fold<double>(0, (s, it) => s + it.price * it.unitsSold);
    final totalCost =
        items.fold<double>(0, (s, it) => s + it.costPrice * it.unitsSold);
    final netProfit = totalRevenue - totalCost;
    final totalUnitsSold = items.fold<int>(0, (s, it) => s + it.unitsSold);
    final profitMargin =
        totalRevenue > 0 ? (netProfit / totalRevenue * 100) : 0;

    // Category breakdown for pie chart
    final catRevenue = <String, double>{};
    for (final it in items) {
      catRevenue[it.category] =
          (catRevenue[it.category] ?? 0) + it.price * it.unitsSold;
    }
    final sortedCats = catRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCats = sortedCats.take(3).toList();
    final totalCatRev = catRevenue.values.fold<double>(0, (s, v) => s + v);

    // Top 5 best-selling items for "Latest Orders"
    final bestSellers = List<StockItem>.from(items)
      ..sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
    final topItems = bestSellers.take(5).toList();
    final tints = [
      kTintPurple,
      kTintMint,
      kTintPeach,
      kTintBlue,
      const Color(0xFFE8F1FF)
    ];
    final icons = [
      Icons.local_fire_department_rounded,
      Icons.trending_up_rounded,
      Icons.star_rounded,
      Icons.shopping_basket_rounded,
      Icons.inventory_2_outlined,
    ];

    // Sparkline from recent category sales
    final sparkPts = <double>[];
    if (sortedCats.length >= 6) {
      for (int i = 0; i < 6; i++) {
        sparkPts.add(sortedCats[i].value);
      }
    } else {
      for (final c in sortedCats) {
        sparkPts.add(c.value);
      }
    }

    String formatKES(double v) {
      if (v >= 1000000) return 'KES ${(v / 1000000).toStringAsFixed(1)}M';
      if (v >= 1000) return 'KES ${(v / 1000).toStringAsFixed(1)}K';
      return 'KES ${v.toStringAsFixed(0)}';
    }

    return NavShell(active: AppScreen.home, go: go, children: [
      AppHeader(go: go, unread: unread),
      Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Hi, '),
            TextSpan(
              text: user?.name ?? 'Shop Owner',
              style:
                  const TextStyle(color: kPurple, fontWeight: FontWeight.w700),
            ),
          ]),
          style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -1)),
      const Text("here's your business overview",
          style: TextStyle(fontSize: 14)),
      const SizedBox(height: 18),
      // ---- Total Revenue Card (tappable → analytics) ----
      GestureDetector(
        onTap: () => go(AppScreen.analytics),
        child: Container(
          height: 116,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: kBlue,
            boxShadow: const [
              BoxShadow(
                  color: Color(0x301E6BFF),
                  blurRadius: 26,
                  offset: Offset(0, 12))
            ],
          ),
          child: Row(children: [
            Container(
              width: 51,
              height: 44,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  color: kBlue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Revenue',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Flexible(
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(formatKES(totalRevenue),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)))),
                      const SizedBox(width: 6),
                      Pill('$totalUnitsSold sold',
                          bg: Color(0x33FFFFFF), fg: Colors.white),
                    ]),
                    const SizedBox(height: 4),
                    Text('from ${items.length} products',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 11)),
                  ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
                width: 60,
                height: 56,
                child:
                    CustomPaint(painter: SparklinePainter(points: sparkPts))),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      // ---- Net Profit Card with live pie (tappable → analytics) ----
      GestureDetector(
        onTap: () => go(AppScreen.analytics),
        child: Container(
          height: 106,
          padding: const EdgeInsets.all(20),
          decoration: cardDeco(Colors.white),
          child: Row(children: [
            SizedBox(
              width: 58,
              height: 58,
              child: CustomPaint(
                  painter: DBPiePainter(
                slices: topCats.isEmpty
                    ? [1.0]
                    : topCats
                        .map((e) =>
                            e.value / (totalCatRev > 0 ? totalCatRev : 1))
                        .toList(),
              )),
            ),
            const SizedBox(width: 21),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Net Profit', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Flexible(
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(formatKES(netProfit),
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)))),
                      const SizedBox(width: 6),
                      Pill('${profitMargin.toStringAsFixed(0)}% margin'),
                    ]),
                    const SizedBox(height: 4),
                    Text('cost: ${formatKES(totalCost)}',
                        style: const TextStyle(color: kMuted, fontSize: 11)),
                  ]),
            ),
          ]),
        ),
      ),
      // ---- Quick Stats Row (tappable → stock) ----
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _quickStat(
              'In Stock',
              '${items.where((i) => !i.isOutOfStock && !i.isLowStock).length}',
              const Color(0xFFE1F6F4),
              const Color(0xFF0F9D85),
              () => go(AppScreen.stock)),
          const SizedBox(width: 8),
          _quickStat(
              'Half Sold',
              '${items.where((i) => i.isHalfSold).length}',
              const Color(0xFFFEF3C7),
              const Color(0xFFD97706),
              () => go(AppScreen.stock)),
          const SizedBox(width: 8),
          _quickStat(
              'Low Stock',
              '${items.where((i) => i.isLowStock).length}',
              const Color(0xFFFFF0DC),
              const Color(0xFFE65100),
              () => go(AppScreen.stock)),
          const SizedBox(width: 8),
          _quickStat(
              'Out',
              '${items.where((i) => i.isOutOfStock).length}',
              const Color(0xFFFFECEB),
              const Color(0xFFD32F2F),
              () => go(AppScreen.stock)),
        ]),
      ),
      const SizedBox(height: 25),
      // ---- Top Sellers / Latest Orders ----
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Top Sellers',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        OutlinedButton.icon(
          onPressed: () => go(AppScreen.stock),
          icon: const Icon(Icons.arrow_forward_rounded, size: 16),
          label: const Text('See All', style: TextStyle(fontSize: 10)),
          iconAlignment: IconAlignment.end,
          style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF484555),
              side: const BorderSide(color: Color(0xFFD9D7E5)),
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact),
        ),
      ]),
      const SizedBox(height: 12),
      for (int i = 0; i < topItems.length; i++)
        GestureDetector(
          onTap: () => go(AppScreen.stock),
          child: Container(
            height: 79,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
                color: tints[i % tints.length],
                borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Icon(icons[i % icons.length],
                    color: const Color(0xFF373448), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(topItems[i].name,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('KES ${topItems[i].price.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ]),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: const Color(0xFF252235),
                    borderRadius: BorderRadius.circular(15)),
                child: Text('${topItems[i].unitsSold} Sold',
                    style: const TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _quickStat(String label, String value, Color bg, Color fg,
      [VoidCallback? onTap]) {
    return SizedBox(
      width: 88,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: fg)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      ),
    );
  }
}

/// Pie chart painter driven by real DB data slices
class DBPiePainter extends CustomPainter {
  final List<double> slices;
  DBPiePainter({required this.slices});

  static const _colors = [
    0xFF7045E5,
    0xFFF2A65E,
    0xFFFFD67B,
    0xFF4FC3F7,
    0xFF81C784
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (int i = 0; i < slices.length; i++) {
      final sweep = slices[i] * 2 * math.pi;
      canvas.drawArc(rect, start, sweep - .03, true,
          Paint()..color = Color(_colors[i % _colors.length]));
      start += sweep;
    }
    canvas.drawCircle(size.center(Offset.zero), size.width * .17,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant DBPiePainter oldDelegate) => true;
}

// ---------- Analytics ----------

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.go, required this.unread});
  final void Function(AppScreen) go;
  final int unread;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String selectedPeriod = 'July 2024';
  static const periods = [
    'Today',
    'This Week',
    'July 2024',
    'This Quarter',
    'Year 2024'
  ];

  String _fmt(double v) {
    if (v >= 1000000) return 'KES ${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return 'KES ${(v / 1000).toStringAsFixed(1)}K';
    return 'KES ${v.toStringAsFixed(0)}';
  }

  void _showPeriodPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Reporting Period',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              for (final p in periods)
                ListTile(
                  title: Text(p,
                      style: TextStyle(
                          fontWeight: selectedPeriod == p
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selectedPeriod == p ? kBlue : kInk)),
                  trailing: selectedPeriod == p
                      ? const Icon(Icons.check_circle_rounded, color: kBlue)
                      : null,
                  onTap: () {
                    setState(() => selectedPeriod = p);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportReport(double revenue, double cost, int units) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = JengaDB.instance;
      await InventoryPdfExportService.shareInventory(
        items: db.items,
        shopName: db.currentUser?.shopName ?? 'JengaBiz shop',
        revenue: revenue,
        cost: cost,
        unitsSold: units,
      );
    } catch (_) {
      if (!mounted || !messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Could not export the stock PDF. Please try again.')),
      );
    }
  }

  Widget _stat(String label, String value, String delta) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: cardDeco(Colors.white),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10)),
            const SizedBox(height: 3),
            FittedBox(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800))),
            const SizedBox(height: 7),
            Pill(delta, bg: const Color(0xFFEDF9F3)),
          ]),
        ),
      );

  Widget _chart(List<({String label, double rev, double cost})> bars,
      double maxVal, double totalRev, double totalCost) {
    final yLabels = [
      _fmt(maxVal),
      _fmt(maxVal * 0.8),
      _fmt(maxVal * 0.6),
      _fmt(maxVal * 0.4),
      _fmt(maxVal * 0.2),
      '0',
    ];

    return SizedBox(
      height: 270,
      child: Stack(children: [
        Positioned.fill(
          bottom: 26,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 52,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final l in yLabels)
                      Text(l,
                          style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF625E70),
                              fontWeight: FontWeight.w600)),
                  ]),
            ),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 6; i++)
                      const Divider(height: 1, color: Color(0xFFE7E6EF)),
                  ]),
            ),
          ]),
        ),
        Positioned.fill(
          left: 54,
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final b in bars)
              SizedBox(
                width: 36,
                child: Column(children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: maxVal > 0
                            ? ((b.rev + b.cost) / maxVal).clamp(0.08, 1.0)
                            : 0.1,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5)),
                          child: Column(children: [
                            Expanded(
                              flex: math.max(1, (b.cost / 100).round()),
                              child: Container(color: const Color(0xFF9EE2DE)),
                            ),
                            const SizedBox(height: 2),
                            Expanded(
                              flex: math.max(1, (b.rev / 100).round()),
                              child: Container(color: const Color(0xFFB095F0)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 26,
                    child: Center(
                        child: Text(b.label,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF625E70),
                                fontWeight: FontWeight.w600))),
                  ),
                ]),
              ),
          ]),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            width: 175,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: kShadow, blurRadius: 20, offset: Offset(0, 8))
                ]),
            child: Column(children: [
              _legend(const Color(0xFF83D8D8), 'Received', _fmt(totalRev)),
              const SizedBox(height: 8),
              _legend(const Color(0xFFA98AF1), 'Spent', _fmt(totalCost)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _legend(Color c, String l, String v) => Row(children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(l, style: const TextStyle(fontSize: 8, color: kMuted)),
        const Spacer(),
        Text(v,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
      ]);

  Widget _insight(IconData icon, String label, String value, Color bg, Color fg,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(icon, color: fg, size: 25),
              Icon(Icons.north_east_rounded, color: fg, size: 16),
            ]),
            const Spacer(),
            Text(label, style: TextStyle(fontSize: 9, color: fg)),
            Text(value,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: fg)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final db = JengaDB.instance;
    final items = db.items;

    // Real DB Analytics
    final totalRevenue =
        items.fold<double>(0, (s, it) => s + it.price * it.unitsSold);
    final totalCost =
        items.fold<double>(0, (s, it) => s + it.costPrice * it.unitsSold);
    final netProfit = totalRevenue - totalCost;
    final totalUnitsSold = items.fold<int>(0, (s, it) => s + it.unitsSold);
    final profitMargin =
        totalRevenue > 0 ? (netProfit / totalRevenue * 100) : 0;
    final lowStockCount =
        items.where((it) => it.isLowStock || it.isOutOfStock).length;
    final categories = db.getCategories().where((c) => c != 'All').toList();

    // Divide 500 items into 5 segments for the bar chart
    final chunkSize = (items.length / 5).ceil();
    final periodLabels = ['1–7', '8–14', '15–21', '22–28', '29–31'];
    final bars = <({String label, double rev, double cost})>[];
    for (int i = 0; i < 5; i++) {
      final start = (i * chunkSize).clamp(0, items.length);
      final end = ((i + 1) * chunkSize).clamp(0, items.length);
      final chunk = items.sublist(start, end);
      final cRev =
          chunk.fold<double>(0, (s, it) => s + it.price * it.unitsSold);
      final cCost =
          chunk.fold<double>(0, (s, it) => s + it.costPrice * it.unitsSold);
      bars.add((label: periodLabels[i], rev: cRev, cost: cCost));
    }
    final maxVal = bars.map((b) => b.rev + b.cost).fold<double>(0, math.max);

    return NavShell(active: AppScreen.analytics, go: widget.go, children: [
      AppHeader(
          go: widget.go,
          unread: widget.unread,
          onBack: () => widget.go(AppScreen.home)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        InkWell(
          onTap: _showPeriodPicker,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(children: [
              Text(selectedPeriod,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, color: kMuted),
            ]),
          ),
        ),
        FilledButton.icon(
          onPressed: () =>
              _exportReport(totalRevenue, totalCost, totalUnitsSold),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
              backgroundColor: kPurple,
              shape: const StadiumBorder(),
              minimumSize: const Size(0, 40)),
        ),
      ]),
      const SizedBox(height: 15),
      Row(children: [
        _stat('Total Spent', _fmt(totalCost),
            '${profitMargin.toStringAsFixed(0)}% profit margin'),
        const SizedBox(width: 12),
        _stat(
            'Total Received', _fmt(totalRevenue), '$totalUnitsSold units sold'),
      ]),
      const SizedBox(height: 20),
      _chart(bars, maxVal, totalRevenue, totalCost),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Business Insights',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          TextButton(
            onPressed: () => widget.go(AppScreen.stock),
            child: const Text('View All in Stock',
                style: TextStyle(
                    fontSize: 11, color: kBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 11,
        crossAxisSpacing: 11,
        childAspectRatio: 1.5,
        children: [
          _insight(
              Icons.shopping_bag_outlined,
              'Total Units Sold',
              '$totalUnitsSold Units',
              kTintPurple,
              const Color(0xFF573C9D),
              () => widget.go(AppScreen.stock)),
          _insight(
              Icons.inventory_2_outlined,
              'Products Managed',
              '${items.length} Items',
              const Color(0xFFDFF6F4),
              const Color(0xFF246A70),
              () => widget.go(AppScreen.stock)),
          _insight(
              Icons.category_outlined,
              'Active Categories',
              '${categories.length} Categories',
              const Color(0xFFFFEAD7),
              const Color(0xFF815735),
              () => widget.go(AppScreen.stock)),
          _insight(
              Icons.warning_amber_rounded,
              'Restock Alerts',
              '$lowStockCount Need Stock',
              kTintBlue,
              const Color(0xFF326083),
              () => widget.go(AppScreen.stock)),
        ],
      ),
    ]);
  }
}

// ---------- Profile ----------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen(
      {super.key,
      required this.go,
      required this.unread,
      required this.onLogout,
      this.onSignInAgain,
      this.onCheckForUpdates,
      this.referralSummaryLoader});
  final void Function(AppScreen) go;
  final int unread;
  final VoidCallback onLogout;
  final VoidCallback? onSignInAgain;
  final VoidCallback? onCheckForUpdates;
  final Future<JengaApiResponse?> Function()? referralSummaryLoader;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _referralExpanded = false;
  bool _referralLoading = false;
  bool _referralLocationSaving = false;
  bool _referralNeedsSignIn = false;
  bool _preferencesLoaded = false;
  Map<String, dynamic>? _referralSummary;
  String? _referralError;

  final prefs = <String, bool>{
    'Biometric login': true,
    'Push notifications': true,
    'Weekly email report': true,
  };

  static const _preferenceKeys = {
    'Biometric login': 'jengabiz_pref_biometric_login',
    'Push notifications': StockNotificationService.preferenceKey,
    'Weekly email report': 'jengabiz_pref_weekly_email_report',
  };

  static const subs = {
    'Biometric login': 'Face ID or fingerprint unlock',
    'Push notifications':
        'Low stock, sold out and 50% sold alerts on this phone',
    'Weekly email report': 'Summary every Monday',
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _toggleReferral() {
    final expanded = !_referralExpanded;
    setState(() => _referralExpanded = expanded);
    if (expanded) unawaited(_loadReferralSummary());
  }

  Future<void> _loadReferralSummary() async {
    if (_referralLoading) return;
    setState(() {
      _referralLoading = true;
      _referralError = null;
    });
    JengaApiResponse? response;
    try {
      response = await (widget.referralSummaryLoader?.call() ??
          JengaApiService.instance.fetchReferralSummary());
    } catch (_) {
      // Keep the profile usable if the request transport fails unexpectedly.
    }
    if (!mounted) return;
    if (response?.succeeded != true) {
      setState(() {
        _referralLoading = false;
        _referralNeedsSignIn = response?.statusCode == 401;
        if (_referralNeedsSignIn) _referralSummary = null;
        _referralError = _referralLoadError(response);
      });
      return;
    }
    final summary = Map<String, dynamic>.from(response!.data);
    setState(() {
      _referralLoading = false;
      _referralNeedsSignIn = false;
      _referralSummary = summary;
    });
    if (summary['hasLocation'] != true) {
      await _detectAndSaveReferralLocation();
    }
  }

  String _referralLoadError(JengaApiResponse? response) {
    if (response == null) {
      return 'Could not reach JengaBiz. Check your connection and try again.';
    }
    if (response.statusCode == 401) {
      return 'Your sign-in needs refreshing. Sign in again to load referral points.';
    }
    final message = response.data['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    if (response.statusCode >= 500) {
      return 'The referral service is temporarily unavailable. Try again shortly.';
    }
    return 'Referral points could not be loaded (error ${response.statusCode}). Try again.';
  }

  Future<void> _detectAndSaveReferralLocation() async {
    if (_referralLocationSaving) return;
    setState(() {
      _referralLocationSaving = true;
      _referralError = null;
    });
    try {
      final detected =
          await LocationBiometricService.instance.detectReferralLocation();
      if (detected == null) {
        throw const FormatException(
            'Turn on Location and allow access to detect your county.');
      }
      if (detected.countryCode != 'KE') {
        throw const FormatException(
            'Refer & Earn is currently available in Kenya only.');
      }
      final response = await JengaApiService.instance.saveReferralLocation(
        county: detected.county,
      );
      if (response?.statusCode == 401) {
        if (!mounted) return;
        setState(() {
          _referralLocationSaving = false;
          _referralNeedsSignIn = true;
          _referralSummary = null;
          _referralError =
              'Your sign-in needs refreshing. Sign in again to load referral points.';
        });
        return;
      }
      if (response?.succeeded != true || response?.data['user'] is! Map) {
        throw FormatException(response?.data['message'] as String? ??
            'Could not save your referral location. Please try again.');
      }
      final user = Map<String, dynamic>.from(response!.data['user'] as Map);
      await JengaDB.instance.persistAuthenticatedAccount(profile: user);
      if (!mounted) return;
      setState(() {
        _referralLocationSaving = false;
        _referralNeedsSignIn = false;
        _referralSummary = {
          ...?_referralSummary,
          'country': 'KE',
          'county': user['county'] ?? detected.county,
          'hasLocation': true,
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _referralLocationSaving = false;
        _referralError = error is FormatException
            ? error.message
            : 'Could not detect your county. Please try again.';
      });
    }
  }

  Widget _referralDetails() {
    final summary = _referralSummary;
    if (_referralLoading && summary == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (summary == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _referralError ?? 'Referral details are not available right now.',
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
            const SizedBox(height: 4),
            _referralActionButton(),
          ],
        ),
      );
    }

    final points = (summary['totalPoints'] as num?)?.toInt() ?? 0;
    final referralCode = summary['referralCode'] as String? ?? '';
    final referralLink = referralCode.isEmpty
        ? null
        : Uri.https(
            'jengabiz.mftechnologies.org',
            '/',
            {'ref': referralCode},
          ).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'Total points',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '$points',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: kBlue,
              ),
            ),
          ],
        ),
        if (referralLink != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Referral link',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Builder(
            builder: (shareContext) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            _shareReferralLink(referralLink, shareContext),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            referralLink,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kBlue,
                              decoration: TextDecoration.underline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          size: 18, color: kBlue),
                      tooltip: 'Copy referral link',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                            ClipboardData(text: referralLink));
                        if (!mounted || !messenger.mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Referral link copied')),
                        );
                      },
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        _inviteReferralContact(referralLink, shareContext),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                    label: const Text('Invite a contact'),
                    style: TextButton.styleFrom(
                      foregroundColor: kBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_referralError != null) ...[
          const SizedBox(height: 8),
          Text(
            _referralError!,
            style: const TextStyle(fontSize: 11, color: Color(0xFFD32F2F)),
          ),
          _referralActionButton(),
        ],
      ],
    );
  }

  Widget _referralActionButton() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _referralLoading || _referralLocationSaving
              ? null
              : _referralNeedsSignIn
                  ? widget.onSignInAgain ?? widget.onLogout
                  : _loadReferralSummary,
          icon: Icon(
            _referralNeedsSignIn ? Icons.login_rounded : Icons.refresh_rounded,
            size: 17,
          ),
          label: Text(_referralNeedsSignIn ? 'Sign in again' : 'Try again'),
          style: TextButton.styleFrom(
            foregroundColor: kBlue,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          ),
        ),
      );

  Future<void> _loadPreferences() async {
    try {
      final stored = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        for (final entry in _preferenceKeys.entries) {
          prefs[entry.key] = stored.getBool(entry.value) ?? true;
        }
        _preferencesLoaded = true;
      });
      if (prefs['Push notifications'] == true) {
        await FirebasePushService.instance.requestPermission();
      }
    } catch (_) {
      if (mounted) setState(() => _preferencesLoaded = true);
    }
  }

  Future<void> _setPreference(String label, bool value) async {
    setState(() => prefs[label] = value);
    try {
      final stored = await SharedPreferences.getInstance();
      await stored.setBool(_preferenceKeys[label]!, value);
      if (label == 'Push notifications' && value) {
        await FirebasePushService.instance.requestPermission();
      } else if (label == 'Push notifications') {
        await FirebasePushService.instance.removeCurrentDevice();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this preference.')),
      );
    }
  }

  Widget _legalRow(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: kTintPurple,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: kBlue, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: kMuted),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: kMuted),
      onTap: onTap,
    );
  }

  Widget _row(
      IconData icon, Color bg, Color fg, String label, VoidCallback onTap,
      {int count = 0}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: kInk))),
          if (count > 0) Pill('$count new', bg: kTintPurple, fg: kPurple),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward_rounded,
              size: 18, color: Color(0xFFB0ADC0)),
        ]),
      ),
    );
  }

  Future<void> _shareReferralLink(
      String referralLink, BuildContext shareContext,
      {String? inviteeName}) async {
    final renderObject = shareContext.findRenderObject();
    final messenger = ScaffoldMessenger.of(context);
    final sharePositionOrigin =
        renderObject is RenderBox && renderObject.hasSize
            ? renderObject.localToGlobal(Offset.zero) & renderObject.size
            : null;

    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'Invite to JengaBiz',
          text: inviteeName == null || inviteeName.trim().isEmpty
              ? 'Grow your shop with JengaBiz. Join using my invite link: $referralLink'
              : 'Hi ${inviteeName.trim()}, grow your shop with JengaBiz. Join using my invite link: $referralLink',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (_) {
      if (!mounted || !messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('Unable to open sharing options. Copy the link instead.'),
        ),
      );
    }
  }

  Future<void> _inviteReferralContact(
    String referralLink,
    BuildContext shareContext,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final permissionGranted =
          await FlutterContacts.requestPermission(readonly: true);
      if (!mounted) return;
      if (!permissionGranted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Allow Contacts access to choose someone to invite. You can still copy or share the link manually.',
            ),
          ),
        );
        return;
      }

      final contact = await FlutterContacts.openExternalPick();
      if (!mounted || contact == null) return;
      await _shareReferralLink(
        referralLink,
        shareContext,
        inviteeName: contact.displayName,
      );
    } catch (_) {
      if (!mounted || !messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Could not open your contacts. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = JengaDB.instance.currentUser;
    final items = JengaDB.instance.items;
    final totalSold = items.fold<int>(0, (s, it) => s + it.unitsSold);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // Top Navigation Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            RoundBtn(
                icon: Icons.arrow_back_rounded,
                onTap: () => widget.go(AppScreen.home)),
            RoundBtn(
              icon: Icons.notifications_none_rounded,
              badge: widget.unread,
              onTap: () => widget.go(AppScreen.notifications),
            ),
          ]),
        ),

        // User Profile Header (Full-width, edge-to-edge)
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              const Center(child: Avatar(size: 84)),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  user?.name ?? 'Shop Owner',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: kInk),
                ),
              ),
              Center(
                child: Text(
                  user?.email ?? 'owner@jengabiz.com',
                  style: const TextStyle(fontSize: 12, color: kMuted),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Pill(
                  '${user?.shopName ?? 'Jenga Super Duka'} • Verified',
                  bg: kTintPurple,
                  fg: kPurple,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Summary Stats (Full-width, edge-to-edge, 50/50 split)
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Units Sold',
                          style: TextStyle(
                              fontSize: 11,
                              color: kMuted,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('$totalSold',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: kInk)),
                    ]),
              ),
              Container(width: 1, height: 38, color: const Color(0xFFECEEF5)),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Stock Catalog',
                          style: TextStyle(
                              fontSize: 11,
                              color: kMuted,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${items.length} Items',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: kInk)),
                    ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Navigation Action Rows (Full-width, edge-to-edge)
        Container(
          width: double.infinity,
          color: Colors.white,
          child: Column(
            children: [
              _row(
                Icons.inventory_2_outlined,
                const Color(0xFFE8EEF8),
                kBlue,
                'Manage Stock & Inventory (${items.length} Items)',
                () => widget.go(AppScreen.stock),
              ),
              const Divider(height: 1, indent: 68, color: Color(0xFFF1F3F9)),
              _row(
                Icons.bar_chart_rounded,
                const Color(0xFFDFF6F4),
                const Color(0xFF246A70),
                'Business Analytics',
                () => widget.go(AppScreen.analytics),
              ),
              const Divider(height: 1, indent: 68, color: Color(0xFFF1F3F9)),
              _row(
                Icons.notifications_none_rounded,
                kTintPurple,
                kPurple,
                'Notifications',
                () => widget.go(AppScreen.notifications),
                count: widget.unread,
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Preferences',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: kMuted)),
        ),

        // Preferences Container (Full-width, edge-to-edge)
        Container(
          width: double.infinity,
          color: Colors.white,
          child: Column(
            children: [
              // Biometric Login Preference (Fingerprint & Face ID)
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: prefs['Biometric login'] ?? true,
                activeColor: kBlue,
                title: const Text('Biometric login (Fingerprint & Face ID)',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: const Text('Quick unlock with Face ID or fingerprint',
                    style: TextStyle(fontSize: 11, color: kMuted)),
                onChanged: _preferencesLoaded
                    ? (v) => _setPreference('Biometric login', v)
                    : null,
              ),
              const Divider(height: 1, indent: 16, color: Color(0xFFF1F3F9)),

              // Standard Preferences
              for (final e in prefs.entries)
                if (e.key != 'Biometric login') ...[
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    value: e.value,
                    activeColor: kBlue,
                    title: Text(e.key,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: Text(subs[e.key] ?? '',
                        style: const TextStyle(fontSize: 11, color: kMuted)),
                    onChanged: _preferencesLoaded
                        ? (v) => _setPreference(e.key, v)
                        : null,
                  ),
                  const Divider(
                      height: 1, indent: 16, color: Color(0xFFF1F3F9)),
                ],

              // Refer & Earn stays collapsed until the user opens it.
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _toggleReferral,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Refer & Earn',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _referralExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: kMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_referralExpanded) ...[
                      _referralDetails(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Privacy & Legal',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kMuted,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.white,
          child: Column(
            children: [
              _legalRow(
                Icons.description_outlined,
                'Terms of Use',
                'Rules for using JengaBiz',
                () => showLegalDocument(context, jengaBizTerms),
              ),
              const Divider(height: 1, indent: 68, color: Color(0xFFF1F3F9)),
              _legalRow(
                Icons.shield_outlined,
                'Privacy Policy',
                'What account and shop data is used',
                () => showLegalDocument(context, jengaBizPrivacy),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'App updates',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kMuted,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.white,
          child: _legalRow(
            Icons.system_update_alt_rounded,
            'Check for updates',
            'Get the latest JengaBiz version',
            widget.onCheckForUpdates ?? () {},
          ),
        ),

        const SizedBox(height: 24),
        Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: 142,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded, size: 17),
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFFFF5F6),
                foregroundColor: const Color(0xFFD23B52),
                side: const BorderSide(color: Color(0xFFF0C6CC)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              label: const Text('Log out',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}
