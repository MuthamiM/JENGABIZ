import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/calculator/presentation/calculator_screen.dart';
import 'features/credit/presentation/balances_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DukaLedgerApp());
}

class DukaLedgerApp extends StatelessWidget {
  const DukaLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Duka Ledger',
      theme: AppTheme.lightTheme,
      home: const MainTabShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainTabShell extends StatefulWidget {
  const MainTabShell({super.key});

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class _MainTabShellState extends State<MainTabShell> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const CalculatorScreen(),
    const BalancesScreen(),
    const Center(child: Text('Stoo / Stock Management')),
    const Center(child: Text('Muhtasari wa Siku / Daily Summary')),
    const Center(child: Text('Mipangilio / Settings')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calculate), label: 'Mauzo'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Madeni'),
          NavigationDestination(icon: Icon(Icons.inventory), label: 'Stoo'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Muhtasari'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Mipangilio'),
        ],
      ),
    );
  }
}
