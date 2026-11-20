import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

class BalancesScreen extends StatelessWidget {
  const BalancesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sampleDebtors = [
      {'name': 'Mama Brian', 'phone': '0712345678', 'debt': 1450.0, 'score': 'Good'},
      {'name': 'John Kamau', 'phone': '0722000111', 'debt': 820.0, 'score': 'Normal'},
      {'name': 'Baba Otis', 'phone': '0733445566', 'debt': 2300.0, 'score': 'Risky'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Deni za Wateja / Credit Ledger')),
      body: ListView.separated(
        itemCount: sampleDebtors.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (ctx, i) {
          final debtor = sampleDebtors[i];
          return ListTile(
            leading: CircleAvatar(child: Text(debtor['name'].toString().substring(0, 1))),
            title: Text(debtor['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${debtor['phone']} • Hali: ${debtor['score']}'),
            trailing: Text(
              '${AppConstants.currency} ${debtor['debt']}',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onTap: () {
              // Open customer detail / record payment / send reminder
            },
          );
        },
      ),
    );
  }
}
