import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kPurple = Color(0xFF6541E5);
const kInk = Color(0xFF17162A);
const kBg = Color(0xFFF8F8FF);
const kMuted = Color(0xFF777487);
const kTintPurple = Color(0xFFEEE8FF);
const kTintMint = Color(0xFFE1F6F4);
const kTintPeach = Color(0xFFFFF0DC);
const kTintBlue = Color(0xFFE2EFFB);
const kShadow = Color(0x14373159);

void main() => runApp(const DukaLedgerApp());

class DukaLedgerApp extends StatelessWidget {
  const DukaLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DUKA LEDGER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(seedColor: kPurple),
        textTheme: GoogleFonts.manropeTextTheme()
            .apply(bodyColor: kInk, displayColor: kInk),
      ),
      home: const Root(),
    );
  }
}

enum AppScreen { welcome, home, analytics, profile, notifications }

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

class _RootState extends State<Root> {
  AppScreen screen = AppScreen.welcome;
  final List<Notice> notices = [
    Notice(1, 'New order received', 'Wireless Headphone x2 was ordered for \$501.50.',
        '2m ago', kTintPurple, Icons.shopping_bag_outlined),
    Notice(2, 'Payment received', '\$1,240.00 has been added to your earnings.',
        '1h ago', kTintMint, Icons.download_rounded),
    Notice(3, 'Low stock alert', 'Running Shoes is down to 12 units.', '3h ago',
        kTintPeach, Icons.inventory_2_outlined),
    Notice(4, 'Delivery completed', 'Order #13620 was delivered to the customer.',
        'Yesterday', kTintBlue, Icons.local_shipping_outlined, read: true),
    Notice(5, 'Monthly report ready', 'Your July 2024 report is ready to export.',
        '2 days ago', kTintPurple, Icons.bar_chart_rounded, read: true),
  ];

  int get unread => notices.where((n) => !n.read).length;
  void go(AppScreen s) => setState(() => screen = s);

  Widget _body() {
    switch (screen) {
      case AppScreen.welcome:
        return WelcomeScreen(onStart: () => go(AppScreen.home));
      case AppScreen.home:
        return HomeScreen(go: go, unread: unread);
      case AppScreen.analytics:
        return AnalyticsScreen(go: go, unread: unread);
      case AppScreen.profile:
        return ProfileScreen(
            go: go, unread: unread, onLogout: () => go(AppScreen.welcome));
      case AppScreen.notifications:
        return NotificationsScreen(
          items: notices,
          onChanged: () => setState(() {}),
          onBack: () => go(AppScreen.home),
        );
    }
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
  const RoundBtn({super.key, required this.icon, required this.onTap, this.badge = 0});
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
              boxShadow: [BoxShadow(color: kShadow, blurRadius: 14, offset: Offset(0, 4))]),
          child: Icon(icon, size: 22),
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
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.go, required this.unread, this.onBack});
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
                onTap: () => go(AppScreen.profile), child: const Avatar(size: 46)),
        Row(children: [
          RoundBtn(
              icon: Icons.notifications_none_rounded,
              badge: unread,
              onTap: () => go(AppScreen.notifications)),
          const SizedBox(width: 9),
          RoundBtn(icon: Icons.sort_rounded, onTap: () => go(AppScreen.profile)),
        ]),
      ]),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFFD0C2FF), Color(0xFF9176EE)])),
      alignment: Alignment.center,
      child: Container(
        width: size * .52,
        height: size * .6,
        decoration: BoxDecoration(
            color: const Color(0xFFEFB58F), borderRadius: BorderRadius.circular(size)),
        alignment: Alignment.center,
        child: Text('A',
            style: TextStyle(
                fontSize: size * .22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF4A2B31))),
      ),
    );
  }
}

/// Scrollable page with a floating nav that hides while scrolling and
/// returns when scrolling ends.
class NavShell extends StatefulWidget {
  const NavShell({super.key, required this.active, required this.go, required this.children});
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
              child: Center(child: FloatingNav(active: widget.active, go: widget.go)),
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
      child: Container(
        width: 52,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: on
              ? const LinearGradient(colors: [Color(0xFF5A3CE5), Color(0xFF8D58EF)])
              : null,
        ),
        child: Icon(icon, color: on ? Colors.white : const Color(0xFF747186)),
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
        boxShadow: const [BoxShadow(color: Color(0x24382F60), blurRadius: 30, offset: Offset(0, 10))],
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
  const Pill(this.text, {super.key, this.bg = const Color(0xFFC8F1DB), this.fg = const Color(0xFF27936A)});
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Text(text,
            style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

BoxDecoration cardDeco(Color c) => BoxDecoration(
    color: c,
    borderRadius: BorderRadius.circular(20),
    boxShadow: c == Colors.white
        ? const [BoxShadow(color: kShadow, blurRadius: 22, offset: Offset(0, 8))]
        : null);

// ---------- Welcome ----------

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});
  final VoidCallback onStart;

  Widget _feature(IconData icon, List<Color> colors, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: colors)),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(fontSize: 11, height: 1.6, color: kMuted)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 25,
                    height: 25,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        gradient: const LinearGradient(
                            colors: [Color(0xFF6B45EB), Color(0xFF9D71FF)])),
                    child: const Text('DL',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  const Text('DUKA LEDGER',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: Color(0xFF706C81))),
                ]),
              ),
              const SizedBox(height: 8),
              Center(
                child: Image.asset('assets/duka-growth-hero.png',
                    height: 250, fit: BoxFit.contain),
              ),
              const SizedBox(height: 8),
              const Text('SMARTER BUSINESS, EVERY DAY',
                  style: TextStyle(
                      color: kPurple, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              const Text('Kickstart Your Business\nGrowth Today',
                  style: TextStyle(fontSize: 27, height: 1.28, fontWeight: FontWeight.w700, letterSpacing: -1)),
              const SizedBox(height: 24),
              _feature(Icons.bar_chart_rounded, const [Color(0xFF4A37DD), Color(0xFF8B61F4)],
                  'Smart lead tracking',
                  'Stay organized and monitor every lead in one place with real-time updates.'),
              _feature(Icons.settings_outlined, const [Color(0xFF3BC2C4), Color(0xFF79E0D8)],
                  'Automated workflow',
                  'Save time with automated tasks, follow-ups, and reminders to close deals faster.'),
            ]),
          ),
        ),
        GestureDetector(
          onTap: onStart,
          child: Container(
            height: 63,
            margin: const EdgeInsets.only(bottom: 26, top: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(colors: [Color(0xFF5938E7), Color(0xFF7549EC)]),
              boxShadow: const [BoxShadow(color: Color(0x456245D9), blurRadius: 26, offset: Offset(0, 12))],
            ),
            child: Stack(alignment: Alignment.center, children: [
              const Text("Let's Get Started",
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              Positioned(
                right: 7,
                child: Container(
                  width: 49,
                  height: 49,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF5938E7)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------- Home ----------

class SparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const pts = [
      Offset(0, .9), Offset(.15, .62), Offset(.28, .7), Offset(.5, .72),
      Offset(.62, .45), Offset(.78, .22), Offset(.9, .45), Offset(1, .05),
    ];
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final p = Offset(pts[i].dx * size.width, pts[i].dy * size.height);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFDED0FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
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
      canvas.drawArc(rect, start, sweep - .03, true, Paint()..color = Color(p[1] as int));
      start += sweep;
    }
    canvas.drawCircle(size.center(Offset.zero), size.width * .17, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.go, required this.unread});
  final void Function(AppScreen) go;
  final int unread;

  static const orders = [
    ('Wireless Headphone', '\$250.75', '150 Units', kTintPurple, Icons.headphones_outlined),
    ('Smart Watch', '\$320.60', '120 Units', kTintMint, Icons.watch_outlined),
    ('Running Shoes', '\$180.45', '80 Units', kTintPeach, Icons.directions_run_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return NavShell(active: AppScreen.home, go: go, children: [
      AppHeader(go: go, unread: unread),
      Text.rich(TextSpan(children: [
        const TextSpan(text: 'Hi, '),
        TextSpan(text: 'Alex Smith', style: TextStyle(color: kPurple, fontWeight: FontWeight.w700)),
      ]), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -1)),
      const Text("here's your business overview", style: TextStyle(fontSize: 14)),
      const SizedBox(height: 18),
      GestureDetector(
        onTap: () => go(AppScreen.analytics),
        child: Container(
          height: 116,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFF5B36E1), Color(0xFFA165EE)]),
            boxShadow: const [BoxShadow(color: Color(0x307044DA), blurRadius: 26, offset: Offset(0, 12))],
          ),
          child: Row(children: [
            Container(
              width: 51,
              height: 44,
              decoration: BoxDecoration(
                  color: const Color(0xFFF8B4A3), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFA75357)),
            ),
            const SizedBox(width: 16),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total Earnings', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Row(children: const [
                Text('\$12,540.90',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(width: 6),
                Pill('↗ 18%'),
              ]),
              const SizedBox(height: 4),
              const Text('vs last month', style: TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
            const Spacer(),
            SizedBox(width: 60, height: 56, child: CustomPaint(painter: SparklinePainter())),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        height: 106,
        padding: const EdgeInsets.all(20),
        decoration: cardDeco(Colors.white),
        child: Row(children: [
          SizedBox(width: 58, height: 58, child: CustomPaint(painter: PiePainter())),
          const SizedBox(width: 21),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Net Profit', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(children: const [
              Text('\$7,540.90', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(width: 6),
              Pill('↗ 18%'),
            ]),
            const SizedBox(height: 4),
            const Text('vs last month', style: TextStyle(color: kMuted, fontSize: 11)),
          ]),
        ]),
      ),
      const SizedBox(height: 25),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Latest Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        OutlinedButton.icon(
          onPressed: () {},
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
      for (final o in orders)
        Container(
          height: 79,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(color: o.$4, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(o.$5, color: const Color(0xFF373448), size: 28),
            ),
            const SizedBox(width: 14),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.$1, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 3),
              Text(o.$2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: const Color(0xFF252235), borderRadius: BorderRadius.circular(15)),
              child: Text(o.$3, style: const TextStyle(color: Colors.white, fontSize: 9)),
            ),
          ]),
        ),
    ]);
  }
}

// ---------- Analytics ----------

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key, required this.go, required this.unread});
  final void Function(AppScreen) go;
  final int unread;

  static const bars = [
    ('1–7', 2.6, 1.2),
    ('8–14', 3.6, 2.0),
    ('15–21', 4.6, 2.3),
    ('22–28', 4.8, 2.8),
    ('29–31', 3.7, 1.7),
  ];
  static const yLabels = ['\$10K', '\$8K', '\$6K', '\$4K', '\$2K', '\$0'];

  Widget _stat(String label, String value, String delta) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: cardDeco(Colors.white),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10)),
            const SizedBox(height: 3),
            FittedBox(
                child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            const SizedBox(height: 7),
            Pill(delta, bg: const Color(0xFFEDF9F3)),
          ]),
        ),
      );

  Widget _chart() {
    return SizedBox(
      height: 270,
      child: Stack(children: [
        Positioned.fill(
          bottom: 26,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 40,
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final l in yLabels) Text(l, style: const TextStyle(fontSize: 10, color: Color(0xFF625E70))),
              ]),
            ),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var i = 0; i < 6; i++) const Divider(height: 1, color: Color(0xFFE7E6EF)),
              ]),
            ),
          ]),
        ),
        Positioned.fill(
          left: 44,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final b in bars)
              SizedBox(
                width: 34,
                child: Column(children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: (b.$2 + b.$3) / 10,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          child: Column(children: [
                            Expanded(flex: (b.$3 * 10).round(), child: Container(color: const Color(0xFF9EE2DE))),
                            const SizedBox(height: 2),
                            Expanded(flex: (b.$2 * 10).round(), child: Container(color: const Color(0xFFB095F0))),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 26,
                    child: Center(child: Text(b.$1, style: const TextStyle(fontSize: 9, color: Color(0xFF625E70)))),
                  ),
                ]),
              ),
          ]),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            width: 180,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: kShadow, blurRadius: 20, offset: Offset(0, 8))]),
            child: Column(children: [
              _legend(const Color(0xFF83D8D8), 'Received', '\$7,200.00'),
              const SizedBox(height: 8),
              _legend(const Color(0xFFA98AF1), 'Spent', '\$5,100.60'),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _legend(Color c, String l, String v) => Row(children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(l, style: const TextStyle(fontSize: 8, color: kMuted)),
        const Spacer(),
        Text(v, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
      ]);

  Widget _insight(IconData icon, String label, String value, Color bg, Color fg) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Icon(icon, color: fg, size: 25),
            Icon(Icons.north_east_rounded, color: fg, size: 16),
          ]),
          const Spacer(),
          Text(label, style: TextStyle(fontSize: 9, color: fg)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return NavShell(active: AppScreen.analytics, go: go, children: [
      AppHeader(go: go, unread: unread, onBack: () => go(AppScreen.home)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: const [
          Text('July 2024', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Icon(Icons.keyboard_arrow_down_rounded, color: kMuted),
        ]),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: kPurple, shape: const StadiumBorder(), minimumSize: const Size(0, 40)),
        ),
      ]),
      const SizedBox(height: 15),
      Row(children: [
        _stat('Total Spent', '\$9,280.60', '↗ 15% vs last month'),
        const SizedBox(width: 12),
        _stat('Total Received', '\$12,540.90', '↗ 18% vs last month'),
      ]),
      const SizedBox(height: 20),
      _chart(),
      const SizedBox(height: 16),
      const Text('Business Insights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 11,
        crossAxisSpacing: 11,
        childAspectRatio: 1.5,
        children: [
          _insight(Icons.shopping_bag_outlined, 'Total Orders', '11,240', kTintPurple, const Color(0xFF573C9D)),
          _insight(Icons.inventory_2_outlined, 'Total Products', '3,126', const Color(0xFFDFF6F4), const Color(0xFF246A70)),
          _insight(Icons.groups_outlined, 'Total Customers', '28,450', const Color(0xFFFFEAD7), const Color(0xFF815735)),
          _insight(Icons.local_shipping_outlined, 'Total Deliveries', '13,620', kTintBlue, const Color(0xFF326083)),
        ],
      ),
    ]);
  }
}

// ---------- Profile ----------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.go, required this.unread, required this.onLogout});
  final void Function(AppScreen) go;
  final int unread;
  final VoidCallback onLogout;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final prefs = <String, bool>{
    'Push notifications': true,
    'Order updates': true,
    'Low stock alerts': true,
    'Weekly email report': false,
    'Biometric login': true,
  };
  static const subs = {
    'Push notifications': 'Alerts on your device',
    'Order updates': 'New orders and deliveries',
    'Low stock alerts': 'When products run low',
    'Weekly email report': 'Summary every Monday',
    'Biometric login': 'Face ID or fingerprint',
  };

  Widget _row(IconData icon, Color bg, Color fg, String label, VoidCallback onTap, {int count = 0}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: kShadow, blurRadius: 18, offset: Offset(0, 6))]),
        child: Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: fg, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          if (count > 0) Pill('$count new', bg: kTintPurple, fg: kPurple),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward_rounded, size: 18),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(23, 0, 23, 32), children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 18),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          RoundBtn(icon: Icons.arrow_back_rounded, onTap: () => widget.go(AppScreen.home)),
          RoundBtn(
              icon: Icons.notifications_none_rounded,
              badge: widget.unread,
              onTap: () => widget.go(AppScreen.notifications)),
        ]),
      ),
      const Center(child: Avatar(size: 88)),
      const SizedBox(height: 10),
      const Center(child: Text('Alex Smith', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      const Center(child: Text('alex@dukaledger.com', style: TextStyle(fontSize: 12, color: kMuted))),
      const SizedBox(height: 8),
      const Center(child: Pill('Duka Ledger Pro', bg: kTintPurple, fg: kPurple)),
      const SizedBox(height: 18),
      Row(children: [
        for (final s in const [('Total Orders', '11,240'), ('Customers', '28,450')])
          Expanded(
            child: Container(
              margin: EdgeInsets.only(right: s.$1 == 'Total Orders' ? 12 : 0),
              padding: const EdgeInsets.all(16),
              decoration: cardDeco(Colors.white),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$1, style: const TextStyle(fontSize: 10)),
                Text(s.$2, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
      ]),
      _row(Icons.notifications_none_rounded, kTintPurple, kPurple, 'Notifications',
          () => widget.go(AppScreen.notifications), count: widget.unread),
      _row(Icons.bar_chart_rounded, const Color(0xFFDFF6F4), const Color(0xFF246A70), 'Business analytics',
          () => widget.go(AppScreen.analytics)),
      const SizedBox(height: 22),
      const Text('Preferences', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Container(
        decoration: cardDeco(Colors.white),
        child: Column(children: [
          for (final e in prefs.entries)
            SwitchListTile(
              value: e.value,
              activeColor: kPurple,
              title: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text(subs[e.key]!, style: const TextStyle(fontSize: 10, color: kMuted)),
              onChanged: (v) => setState(() => prefs[e.key] = v),
            ),
        ]),
      ),
      const SizedBox(height: 18),
      SizedBox(
        height: 50,
        child: OutlinedButton(
          onPressed: widget.onLogout,
          style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFFFF5F6),
              foregroundColor: const Color(0xFFD23B52),
              side: const BorderSide(color: Color(0xFFF0C6CC)),
              shape: const StadiumBorder()),
          child: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

// ---------- Notifications ----------

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.items, required this.onChanged, required this.onBack});
  final List<Notice> items;
  final VoidCallback onChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final unread = items.where((n) => !n.read).length;
    return ListView(padding: const EdgeInsets.fromLTRB(23, 0, 23, 32), children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 18),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          RoundBtn(icon: Icons.arrow_back_rounded, onTap: onBack),
          FilledButton(
            onPressed: unread == 0
                ? null
                : () {
                    for (final n in items) {
                      n.read = true;
                    }
                    onChanged();
                  },
            style: FilledButton.styleFrom(backgroundColor: kPurple, shape: const StadiumBorder()),
            child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Notifications', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Pill('$unread new', bg: kTintPurple, fg: kPurple),
      ]),
      const SizedBox(height: 14),
      if (items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text("You're all caught up.", style: TextStyle(color: kMuted))),
        ),
      for (final n in List<Notice>.of(items))
        Opacity(
          opacity: n.read ? .75 : 1,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: n.tone, borderRadius: BorderRadius.circular(18)),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                n.read = true;
                onChanged();
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(n.icon, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(n.body, style: const TextStyle(fontSize: 11, color: Color(0xFF5D596C), height: 1.4)),
                      const SizedBox(height: 2),
                      Text(n.time, style: const TextStyle(fontSize: 9, color: Color(0xFF8A8698))),
                    ]),
                  ),
                  if (!n.read)
                    Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: const BoxDecoration(color: kPurple, shape: BoxShape.circle)),
                  GestureDetector(
                    onTap: () {
                      items.removeWhere((x) => x.id == n.id);
                      onChanged();
                    },
                    child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF8A8698)),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}
