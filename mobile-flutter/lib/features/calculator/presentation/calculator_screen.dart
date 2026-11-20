import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  double runningTotal = 0.0;
  String currentInput = '';
  final List<Map<String, dynamic>> selectedItems = [];

  // Quick tap frequent items
  final List<Map<String, dynamic>> quickItems = [
    {'name': 'Sukuma (Fungu)', 'price': 20.0},
    {'name': 'Nyanya (3pcs)', 'price': 50.0},
    {'name': 'Kitunguu (Fungu)', 'price': 30.0},
    {'name': 'Maziwa Mala (500ml)', 'price': 65.0},
    {'name': 'Mkate (Broadways)', 'price': 65.0},
    {'name': 'Kiberiti (Matchbox)', 'price': 5.0},
  ];

  void _addItem(String name, double price) {
    setState(() {
      selectedItems.add({'name': name, 'price': price, 'qty': 1});
      runningTotal += price;
    });
  }

  void _finishSale(String saleType) {
    if (runningTotal <= 0) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(saleType == 'cash' ? 'Uza kwa Pesa Taslimu (Cash)' : 'Weka kwa Deni (Credit)'),
        content: Text('Jumla: ${AppConstants.currency} ${runningTotal.toStringAsFixed(2)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ghairi')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                runningTotal = 0.0;
                selectedItems.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mauzo yamerekodiwa na stoo imepunguzwa!')),
              );
            },
            child: const Text('Thibitisha'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kikokotoo cha Mauzo / Calculator')),
      body: Column(
        children: [
          // Running Total Display
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.green.shade50,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('JUMLA / TOTAL', style: TextStyle(fontSize: 14, color: Colors.grey)),
                Text(
                  '${AppConstants.currency} ${runningTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
          ),
          // Quick Tap Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: quickItems.length,
              itemBuilder: (ctx, i) {
                final item = quickItems[i];
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade100, foregroundColor: Colors.black),
                  onPressed: () => _addItem(item['name'], item['price']),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item['name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${AppConstants.currency} ${item['price']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                );
              },
            ),
          ),
          // Action Buttons: Cash vs Put on Credit
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: () => _finishSale('cash'),
                    child: const Text('PESA TASLIMU\n(Cash Sale)', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                    onPressed: () => _finishSale('credit'),
                    child: const Text('WEKA KWA DENI\n(Put on Credit)', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
