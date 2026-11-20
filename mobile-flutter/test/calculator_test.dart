import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Calculator item price accumulation', () {
    double total = 0.0;
    total += 20.0; // Sukuma
    total += 50.0; // Nyanya
    expect(total, 70.0);
  });
}
