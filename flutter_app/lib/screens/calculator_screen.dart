import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _kBlue = Color(0xFF1E6BFF);
const Color _kInk = Color(0xFF17162A);
const Color _kBg = Color(0xFFF8F8FF);
const Color _kMuted = Color(0xFF777487);
const Color _kTintMint = Color(0xFFE1F6F4);
const Color _kGreen = Color(0xFF0F9D85);
const Color _kTintPeach = Color(0xFFFFF0DC);
const Color _kOrange = Color(0xFFE65100);
const Color _kTintPurple = Color(0xFFE8F1FF);

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({
    super.key,
    required this.onBack,
  });

  final VoidCallback onBack;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

enum CalculatorTool {
  margin,
  kraTax,
  loan,
  breakEven,
  quickMath,
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  CalculatorTool _activeTool = CalculatorTool.margin;

  // --- 1. Margin & Markup State ---
  final TextEditingController _costCtrl = TextEditingController(text: '500');
  final TextEditingController _handlingCtrl = TextEditingController(text: '0');
  final TextEditingController _marginPercentCtrl =
      TextEditingController(text: '25');
  final TextEditingController _sellingPriceCtrl =
      TextEditingController(text: '667');
  bool _marginFromPrice = false;

  // --- 2. KRA Tax State ---
  final TextEditingController _taxAmountCtrl =
      TextEditingController(text: '1160');
  String _taxType = 'vat_inclusive'; // vat_inclusive, vat_exclusive, tot, wht

  // --- 3. Loan Repayment State ---
  final TextEditingController _loanPrincipalCtrl =
      TextEditingController(text: '5000');
  final TextEditingController _loanRateCtrl =
      TextEditingController(text: '8.0');
  final TextEditingController _loanTermCtrl = TextEditingController(text: '14');
  final TextEditingController _loanFeeCtrl = TextEditingController(text: '0');
  String _rateFrequency = 'annual'; // annual, monthly, daily
  String _termUnit = 'days'; // days, months

  // --- 4. Break-Even State ---
  final TextEditingController _rentCtrl = TextEditingController(text: '15000');
  final TextEditingController _powerWaterCtrl =
      TextEditingController(text: '3000');
  final TextEditingController _wagesCtrl = TextEditingController(text: '12000');
  final TextEditingController _licensesCtrl =
      TextEditingController(text: '2000');
  final TextEditingController _otherFixedCtrl =
      TextEditingController(text: '3000');
  final TextEditingController _grossMarginCtrl =
      TextEditingController(text: '25');
  final TextEditingController _targetProfitCtrl =
      TextEditingController(text: '20000');
  int _tradingDays = 26;

  // --- 5. Quick Math State ---
  String _mathExpression = '';
  String _mathResult = '0';
  bool _justCalculated = false;

  @override
  void dispose() {
    _costCtrl.dispose();
    _handlingCtrl.dispose();
    _marginPercentCtrl.dispose();
    _sellingPriceCtrl.dispose();
    _taxAmountCtrl.dispose();
    _loanPrincipalCtrl.dispose();
    _loanRateCtrl.dispose();
    _loanTermCtrl.dispose();
    _loanFeeCtrl.dispose();
    _rentCtrl.dispose();
    _powerWaterCtrl.dispose();
    _wagesCtrl.dispose();
    _licensesCtrl.dispose();
    _otherFixedCtrl.dispose();
    _grossMarginCtrl.dispose();
    _targetProfitCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) {
    if (v.isNaN || v.isInfinite) return '0.00';
    final parts = v.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  void _showInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded, color: _kBlue),
            SizedBox(width: 8),
            Text('4 Business Functions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Profit Margin & Markup',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kInk),
              ),
              SizedBox(height: 2),
              Text(
                'Avoid selling at a loss amidst rising wholesale prices and transport costs. Differentiates true profit margin from simple markup.',
                style: TextStyle(fontSize: 12, color: _kMuted),
              ),
              SizedBox(height: 12),
              Text(
                '2. KRA eTIMS & Tax Calculator',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kInk),
              ),
              SizedBox(height: 2),
              Text(
                'Quickly extract 16% VAT from gross receipts, compute 16% VAT for quotes, 1.5% Turnover Tax (TOT) for small shops, or 5% WHT.',
                style: TextStyle(fontSize: 12, color: _kMuted),
              ),
              SizedBox(height: 12),
              Text(
                '3. Mobile & Hustler Loan Repayment',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kInk),
              ),
              SizedBox(height: 2),
              Text(
                'Know the true borrowing cost of digital loans (Hustler Fund, Fuliza, M-Shwari, Chama) with daily/monthly repayment schedules.',
                style: TextStyle(fontSize: 12, color: _kMuted),
              ),
              SizedBox(height: 12),
              Text(
                '4. Break-Even & Daily Sales Target',
                style: TextStyle(fontWeight: FontWeight.bold, color: _kInk),
              ),
              SizedBox(height: 2),
              Text(
                'Calculates the exact daily sales required to cover shop rent, electricity, licenses, and hit your monthly livelihood income goal.',
                style: TextStyle(fontSize: 12, color: _kMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it',
                style: TextStyle(color: _kBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              _buildTopBar(),
              _buildToolSelector(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                  child: _buildActiveCalculator(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onBack,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      size: 20, color: _kInk),
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Business Calculator',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _kInk,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Smart MSME Financial Tools',
                    style: TextStyle(fontSize: 11, color: _kMuted),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            onPressed: _showInfoDialog,
            icon: const Icon(Icons.info_outline_rounded,
                color: _kBlue, size: 24),
            tooltip: 'About Functions',
          ),
        ],
      ),
    );
  }

  Widget _buildToolSelector() {
    final tools = [
      (CalculatorTool.margin, 'Margin & Price', Icons.trending_up_rounded),
      (CalculatorTool.kraTax, 'KRA eTIMS & Tax', Icons.receipt_long_rounded),
      (CalculatorTool.loan, 'Loans & Interest', Icons.payments_outlined),
      (CalculatorTool.breakEven, 'Break-Even Target', Icons.track_changes_rounded),
      (CalculatorTool.quickMath, 'Quick Math', Icons.calculate_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: tools.map((t) {
          final isSelected = _activeTool == t.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(
                t.$3,
                size: 16,
                color: isSelected ? Colors.white : _kInk,
              ),
              label: Text(
                t.$2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : _kInk,
                ),
              ),
              selected: isSelected,
              selectedColor: _kBlue,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isSelected ? _kBlue : const Color(0xFFE2E4EB),
                ),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() => _activeTool = t.$1);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActiveCalculator() {
    switch (_activeTool) {
      case CalculatorTool.margin:
        return _buildMarginCalculator();
      case CalculatorTool.kraTax:
        return _buildTaxCalculator();
      case CalculatorTool.loan:
        return _buildLoanCalculator();
      case CalculatorTool.breakEven:
        return _buildBreakEvenCalculator();
      case CalculatorTool.quickMath:
        return _buildQuickMathCalculator();
    }
  }

  // ==========================================================
  // 1. PROFIT MARGIN & MARKUP CALCULATOR
  // ==========================================================
  Widget _buildMarginCalculator() {
    final cost = double.tryParse(_costCtrl.text.trim()) ?? 0.0;
    final handling = double.tryParse(_handlingCtrl.text.trim()) ?? 0.0;
    final totalCost = cost + handling;

    double sellingPrice = 0.0;
    double grossProfit = 0.0;
    double marginPercent = 0.0;
    double markupPercent = 0.0;

    if (_marginFromPrice) {
      sellingPrice = double.tryParse(_sellingPriceCtrl.text.trim()) ?? 0.0;
      grossProfit = sellingPrice - totalCost;
      if (sellingPrice > 0) {
        marginPercent = (grossProfit / sellingPrice) * 100;
      }
      if (totalCost > 0) {
        markupPercent = (grossProfit / totalCost) * 100;
      }
    } else {
      marginPercent = double.tryParse(_marginPercentCtrl.text.trim()) ?? 0.0;
      if (marginPercent < 100 && marginPercent >= 0) {
        final factor = 1.0 - (marginPercent / 100.0);
        sellingPrice = factor > 0 ? (totalCost / factor) : totalCost;
        grossProfit = sellingPrice - totalCost;
        if (totalCost > 0) {
          markupPercent = (grossProfit / totalCost) * 100;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          title: 'Pricing Strategy Mode',
          child: Row(
            children: [
              Expanded(
                child: _buildChoiceTab(
                  label: 'Price from Margin',
                  isSelected: !_marginFromPrice,
                  onTap: () => setState(() => _marginFromPrice = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildChoiceTab(
                  label: 'Margin from Price',
                  isSelected: _marginFromPrice,
                  onTap: () => setState(() => _marginFromPrice = true),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: 'Cost Inputs',
          child: Column(
            children: [
              _buildInputField(
                controller: _costCtrl,
                label: 'Item Buying / Wholesale Cost (KES)',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              _buildInputField(
                controller: _handlingCtrl,
                label: 'Packaging, Boda/Transport per unit (KES)',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (!_marginFromPrice) ...[
                _buildInputField(
                  controller: _marginPercentCtrl,
                  label: 'Desired Profit Margin (%)',
                  suffixText: '%',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                _buildPresetChips(
                  presets: [15, 20, 25, 30, 40, 50],
                  currentVal: double.tryParse(_marginPercentCtrl.text.trim()),
                  onSelect: (p) => setState(() {
                    _marginPercentCtrl.text = p.toString();
                  }),
                ),
              ] else ...[
                _buildInputField(
                  controller: _sellingPriceCtrl,
                  label: 'Customer Retail Selling Price (KES)',
                  prefixText: 'KES ',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildResultCard(
          accentColor: _kBlue,
          title: 'Pricing & Profit Summary',
          subtitle: 'Protects business from wholesale inflation',
          children: [
            _buildResultRow(
              'Total Unit Cost (Buying + Transport)',
              'KES ${_fmt(totalCost)}',
            ),
            const Divider(height: 18),
            _buildResultRow(
              'Recommended Selling Price',
              'KES ${_fmt(sellingPrice)}',
              isHighlight: true,
              highlightColor: _kBlue,
            ),
            _buildResultRow(
              'Gross Profit per Item',
              'KES ${_fmt(grossProfit)}',
              isHighlight: grossProfit > 0,
              highlightColor: grossProfit >= 0 ? _kGreen : Colors.red,
            ),
            const Divider(height: 18),
            _buildResultRow(
              'Gross Profit Margin',
              '${marginPercent.toStringAsFixed(1)}%',
            ),
            _buildResultRow(
              'Markup on Cost',
              '${markupPercent.toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kTintPurple,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                sellingPrice > 0
                    ? '💡 For every KES 100 collected, KES ${marginPercent.clamp(0, 100).toStringAsFixed(1)} is gross profit and KES ${(100 - marginPercent).clamp(0, 100).toStringAsFixed(1)} covers your inventory expenses.'
                    : 'Enter cost values above to see recommendations.',
                style: const TextStyle(fontSize: 11, color: _kInk),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================================
  // 2. KRA eTIMS & TAX CALCULATOR
  // ==========================================================
  Widget _buildTaxCalculator() {
    final amount = double.tryParse(_taxAmountCtrl.text.trim()) ?? 0.0;

    double netAmount = 0.0;
    double taxAmount = 0.0;
    double grossAmount = 0.0;
    String taxName = '';
    String legalNote = '';

    switch (_taxType) {
      case 'vat_inclusive':
        taxName = '16% VAT Extracted';
        grossAmount = amount;
        netAmount = amount / 1.16;
        taxAmount = grossAmount - netAmount;
        legalNote =
            'For KRA eTIMS receipts: KES ${_fmt(taxAmount)} is the 16% VAT component to remit; your shop keeps KES ${_fmt(netAmount)}.';
        break;
      case 'vat_exclusive':
        taxName = '16% VAT Added';
        netAmount = amount;
        taxAmount = amount * 0.16;
        grossAmount = netAmount + taxAmount;
        legalNote =
            'Add 16% VAT when quoting clients or institutional buyers requiring tax-exclusive pricing.';
        break;
      case 'tot':
        taxName = 'Turnover Tax (1.5% TOT)';
        grossAmount = amount;
        taxAmount = amount * 0.015;
        netAmount = grossAmount - taxAmount;
        legalNote =
            'Applies to Kenyan small businesses with gross sales under KES 25M/year. Due on or before the 20th of the following month on iTax.';
        break;
      case 'wht':
        taxName = 'Withholding Tax (5% WHT)';
        grossAmount = amount;
        taxAmount = amount * 0.05;
        netAmount = grossAmount - taxAmount;
        legalNote =
            '5% withholding on professional services, consultancy, and supply contracts deducted at source.';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          title: 'Select Tax / Compliance Rule',
          child: Column(
            children: [
              _buildTaxOptionTile(
                id: 'vat_inclusive',
                title: '16% VAT Extract (Inclusive)',
                desc: 'Extract VAT already included in customer payment',
              ),
              const SizedBox(height: 8),
              _buildTaxOptionTile(
                id: 'vat_exclusive',
                title: '16% VAT Add (Exclusive)',
                desc: 'Add 16% VAT to invoice / quote for a client',
              ),
              const SizedBox(height: 8),
              _buildTaxOptionTile(
                id: 'tot',
                title: 'Turnover Tax (1.5% TOT)',
                desc: 'Small business monthly tax for sales under KES 25M',
              ),
              const SizedBox(height: 8),
              _buildTaxOptionTile(
                id: 'wht',
                title: 'Withholding Tax (5% WHT)',
                desc: '5% tax deducted on tenders, supplies, and services',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: 'Amount to Calculate',
          child: _buildInputField(
            controller: _taxAmountCtrl,
            label: _taxType == 'vat_exclusive'
                ? 'Net Amount before Tax (KES)'
                : 'Gross Transaction / Sales Amount (KES)',
            prefixText: 'KES ',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 14),
        _buildResultCard(
          accentColor: _kGreen,
          title: 'KRA Tax & eTIMS Breakdown',
          subtitle: taxName,
          children: [
            _buildResultRow(
              'Net Business Revenue',
              'KES ${_fmt(netAmount)}',
              isHighlight: true,
              highlightColor: _kGreen,
            ),
            _buildResultRow(
              'Tax Obligation ($taxName)',
              'KES ${_fmt(taxAmount)}',
              isHighlight: true,
              highlightColor: _kOrange,
            ),
            const Divider(height: 18),
            _buildResultRow(
              'Gross Total Amount',
              'KES ${_fmt(grossAmount)}',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kTintMint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '🇰🇪 $legalNote',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF134E4A),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTaxOptionTile({
    required String id,
    required String title,
    required String desc,
  }) {
    final isSelected = _taxType == id;
    return GestureDetector(
      onTap: () => setState(() => _taxType = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _kTintMint : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _kGreen : const Color(0xFFE2E4EB),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? _kGreen : _kMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      color: _kInk,
                    ),
                  ),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 11, color: _kMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // 3. LOAN & HUSTLER FUND REPAYMENT CALCULATOR
  // ==========================================================
  Widget _buildLoanCalculator() {
    final principal = double.tryParse(_loanPrincipalCtrl.text.trim()) ?? 0.0;
    final rate = double.tryParse(_loanRateCtrl.text.trim()) ?? 0.0;
    final term = double.tryParse(_loanTermCtrl.text.trim()) ?? 0.0;
    final fee = double.tryParse(_loanFeeCtrl.text.trim()) ?? 0.0;

    // Convert term to days for uniform interest calculation
    double durationInDays = _termUnit == 'months' ? (term * 30.0) : term;
    if (durationInDays <= 0) durationInDays = 1;

    double totalInterest = 0.0;
    if (_rateFrequency == 'daily') {
      totalInterest = principal * (rate / 100.0) * durationInDays;
    } else if (_rateFrequency == 'monthly') {
      totalInterest = principal * (rate / 100.0) * (durationInDays / 30.0);
    } else {
      // Annual (e.g. Hustler Fund 8% p.a.)
      totalInterest = principal * (rate / 100.0) * (durationInDays / 365.0);
    }

    final totalCostOfCredit = totalInterest + fee;
    final totalRepayment = principal + totalCostOfCredit;
    final dailyRepayment =
        durationInDays > 0 ? (totalRepayment / durationInDays) : totalRepayment;
    final effectiveCostPercent =
        principal > 0 ? (totalCostOfCredit / principal * 100.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          title: 'Quick Loan Presets',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildLoanPresetChip(
                label: '🇰🇪 Hustler Fund (8% p.a., 14d)',
                onTap: () => setState(() {
                  _loanRateCtrl.text = '8.0';
                  _rateFrequency = 'annual';
                  _loanTermCtrl.text = '14';
                  _termUnit = 'days';
                  _loanFeeCtrl.text = '0';
                }),
              ),
              _buildLoanPresetChip(
                label: '📱 M-Shwari / Bank (7.5% / 30d)',
                onTap: () => setState(() {
                  _loanRateCtrl.text = '7.5';
                  _rateFrequency = 'monthly';
                  _loanTermCtrl.text = '30';
                  _termUnit = 'days';
                  _loanFeeCtrl.text = '0';
                }),
              ),
              _buildLoanPresetChip(
                label: '⚡ Fuliza / Overdraft (~1% daily)',
                onTap: () => setState(() {
                  _loanRateCtrl.text = '1.0';
                  _rateFrequency = 'daily';
                  _loanTermCtrl.text = '7';
                  _termUnit = 'days';
                  _loanFeeCtrl.text = '0';
                }),
              ),
              _buildLoanPresetChip(
                label: '🤝 Chama Loan (10% monthly)',
                onTap: () => setState(() {
                  _loanRateCtrl.text = '10.0';
                  _rateFrequency = 'monthly';
                  _loanTermCtrl.text = '1';
                  _termUnit = 'months';
                  _loanFeeCtrl.text = '0';
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: 'Loan Details',
          child: Column(
            children: [
              _buildInputField(
                controller: _loanPrincipalCtrl,
                label: 'Loan Principal Amount (KES)',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildInputField(
                      controller: _loanRateCtrl,
                      label: 'Interest Rate (%)',
                      suffixText: '%',
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _rateFrequency,
                      decoration: InputDecoration(
                        labelText: 'Rate Period',
                        labelStyle: const TextStyle(fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E4EB)),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'annual', child: Text('Annual (p.a.)')),
                        DropdownMenuItem(
                            value: 'monthly', child: Text('Monthly')),
                        DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _rateFrequency = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildInputField(
                      controller: _loanTermCtrl,
                      label: 'Term / Duration',
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _termUnit,
                      decoration: InputDecoration(
                        labelText: 'Time Unit',
                        labelStyle: const TextStyle(fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E4EB)),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'days', child: Text('Days')),
                        DropdownMenuItem(
                            value: 'months', child: Text('Months')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _termUnit = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildInputField(
                controller: _loanFeeCtrl,
                label: 'Processing Fee / Ledger Charge (KES)',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildResultCard(
          accentColor: const Color(0xFF7045E5),
          title: 'Repayment & Credit Cost',
          subtitle:
              'For duration of ${durationInDays.toStringAsFixed(0)} days',
          children: [
            _buildResultRow(
              'Total Repayment Due',
              'KES ${_fmt(totalRepayment)}',
              isHighlight: true,
              highlightColor: const Color(0xFF7045E5),
            ),
            _buildResultRow(
              'Total Cost of Credit (Interest + Fees)',
              'KES ${_fmt(totalCostOfCredit)}',
              isHighlight: true,
              highlightColor: _kOrange,
            ),
            const Divider(height: 18),
            _buildResultRow(
              'Principal Borrowed',
              'KES ${_fmt(principal)}',
            ),
            _buildResultRow(
              'Calculated Interest',
              'KES ${_fmt(totalInterest)}',
            ),
            _buildResultRow(
              'Daily Required Installment',
              'KES ${_fmt(dailyRepayment)} / day',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '📊 Real Cost of Credit: ${effectiveCostPercent.toStringAsFixed(1)}% of borrowed amount. ${effectiveCostPercent > 15 ? '⚠️ High borrowing cost: ensure your business margin exceeds this rate.' : '✅ Affordable short-term credit.'}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF581C87),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoanPresetChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, color: _kInk)),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDCDFEA)),
      ),
      onPressed: onTap,
    );
  }

  // ==========================================================
  // 4. BREAK-EVEN & DAILY SURVIVAL SALES TARGET
  // ==========================================================
  Widget _buildBreakEvenCalculator() {
    final rent = double.tryParse(_rentCtrl.text.trim()) ?? 0.0;
    final power = double.tryParse(_powerWaterCtrl.text.trim()) ?? 0.0;
    final wages = double.tryParse(_wagesCtrl.text.trim()) ?? 0.0;
    final licenses = double.tryParse(_licensesCtrl.text.trim()) ?? 0.0;
    final other = double.tryParse(_otherFixedCtrl.text.trim()) ?? 0.0;
    final totalFixedOverhead = rent + power + wages + licenses + other;

    final margin = double.tryParse(_grossMarginCtrl.text.trim()) ?? 25.0;
    final targetProfit = double.tryParse(_targetProfitCtrl.text.trim()) ?? 0.0;

    final marginFraction = (margin / 100.0).clamp(0.01, 1.0);
    final monthlyBreakEvenSales = totalFixedOverhead / marginFraction;
    final dailyBreakEvenSales =
        _tradingDays > 0 ? (monthlyBreakEvenSales / _tradingDays) : 0.0;

    final monthlySalesWithProfit =
        (totalFixedOverhead + targetProfit) / marginFraction;
    final dailySalesWithProfit =
        _tradingDays > 0 ? (monthlySalesWithProfit / _tradingDays) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          title: 'Monthly Fixed Shop Overhead (KES)',
          child: Column(
            children: [
              _buildInputField(
                controller: _rentCtrl,
                label: 'Shop / Stall Rent',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _buildInputField(
                controller: _powerWaterCtrl,
                label: 'Electricity Token & Water',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _buildInputField(
                controller: _wagesCtrl,
                label: 'Staff Wages / Assistant Salary',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _buildInputField(
                controller: _licensesCtrl,
                label: 'County Business Permit & KPLC/Internet',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _buildInputField(
                controller: _otherFixedCtrl,
                label: 'Other Fixed Expenses (Security, Waste, etc.)',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: 'Margin & Profit Ambition',
          child: Column(
            children: [
              _buildInputField(
                controller: _grossMarginCtrl,
                label: 'Average Gross Profit Margin (%)',
                suffixText: '%',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _buildInputField(
                controller: _targetProfitCtrl,
                label: 'Desired Monthly Personal Take-Home (KES)',
                prefixText: 'KES ',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Trading Days / Month:',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('$_tradingDays days',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _kBlue)),
                ],
              ),
              Slider(
                value: _tradingDays.toDouble(),
                min: 15,
                max: 31,
                divisions: 16,
                activeColor: _kBlue,
                label: '$_tradingDays days',
                onChanged: (val) =>
                    setState(() => _tradingDays = val.round()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildResultCard(
          accentColor: _kOrange,
          title: 'Daily Sales Survival & Profit Target',
          subtitle:
              'Total Monthly Overhead: KES ${_fmt(totalFixedOverhead)}',
          children: [
            _buildResultRow(
              'Daily Survival Sales (Break-Even)',
              'KES ${_fmt(dailyBreakEvenSales)} / day',
              isHighlight: true,
              highlightColor: _kOrange,
            ),
            _buildResultRow(
              'Monthly Break-Even Revenue',
              'KES ${_fmt(monthlyBreakEvenSales)}',
            ),
            const Divider(height: 18),
            _buildResultRow(
              'Target Daily Sales (With Take-Home)',
              'KES ${_fmt(dailySalesWithProfit)} / day',
              isHighlight: true,
              highlightColor: _kGreen,
            ),
            _buildResultRow(
              'Target Monthly Total Sales',
              'KES ${_fmt(monthlySalesWithProfit)}',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kTintPeach,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '🎯 Survival Target: Ringing up KES ${_fmt(dailyBreakEvenSales)} every day covers all your shop bills without losing money. Ringing up KES ${_fmt(dailySalesWithProfit)} secures your KES ${_fmt(targetProfit)} monthly income.',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7C2D12),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================================
  // 5. QUICK MATH KEYPAD CALCULATOR
  // ==========================================================
  Widget _buildQuickMathCalculator() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 15,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _mathExpression.isEmpty ? '0' : _mathExpression,
                style: const TextStyle(
                  fontSize: 18,
                  color: _kMuted,
                  letterSpacing: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _mathResult,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildKeypad(),
      ],
    );
  }

  Widget _buildKeypad() {
    final rows = [
      ['C', '(', ')', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '-'],
      ['1', '2', '3', '+'],
      ['0', '.', '⌫', '='],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: row.map((btn) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _buildKeypadButton(btn),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeypadButton(String label) {
    final isOperator = {'÷', '×', '-', '+', '='}.contains(label);
    final isAction = {'C', '(', ')', '⌫'}.contains(label);
    final isEquals = label == '=';

    Color bgColor = Colors.white;
    Color fgColor = _kInk;

    if (isEquals) {
      bgColor = _kBlue;
      fgColor = Colors.white;
    } else if (isOperator) {
      bgColor = const Color(0xFFE8EEF8);
      fgColor = _kBlue;
    } else if (isAction) {
      bgColor = const Color(0xFFF1F3F9);
      fgColor = const Color(0xFF5F5D70);
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      elevation: isEquals ? 3 : 1,
      shadowColor: const Color(0x14000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _handleKeypadTap(label),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight:
                  isOperator || isEquals ? FontWeight.w800 : FontWeight.w600,
              color: fgColor,
            ),
          ),
        ),
      ),
    );
  }

  void _handleKeypadTap(String label) {
    setState(() {
      if (label == 'C') {
        _mathExpression = '';
        _mathResult = '0';
        _justCalculated = false;
      } else if (label == '⌫') {
        if (_mathExpression.isNotEmpty) {
          _mathExpression =
              _mathExpression.substring(0, _mathExpression.length - 1);
        }
      } else if (label == '=') {
        _evaluateMath();
        _justCalculated = true;
      } else {
        if (_justCalculated && {'+', '-', '×', '÷'}.contains(label)) {
          _mathExpression = _mathResult + label;
          _justCalculated = false;
        } else if (_justCalculated && !{'+', '-', '×', '÷'}.contains(label)) {
          _mathExpression = label;
          _justCalculated = false;
        } else {
          _mathExpression += label;
        }
      }
    });
  }

  void _evaluateMath() {
    try {
      final sanitized = _mathExpression
          .replaceAll('×', '*')
          .replaceAll('÷', '/');
      if (sanitized.trim().isEmpty) return;

      final res = _simpleEval(sanitized);
      if (res != null) {
        if (res % 1 == 0) {
          _mathResult = res.toInt().toString();
        } else {
          _mathResult = res.toStringAsFixed(2);
        }
      } else {
        _mathResult = 'Error';
      }
    } catch (_) {
      _mathResult = 'Error';
    }
  }

  double? _simpleEval(String expr) {
    // Basic parser for +, -, *, /
    try {
      List<String> tokens = [];
      String current = '';
      for (int i = 0; i < expr.length; i++) {
        final c = expr[i];
        if (c == '+' || c == '-' || c == '*' || c == '/') {
          if (current.isNotEmpty) {
            tokens.add(current);
            current = '';
          }
          tokens.add(c);
        } else {
          current += c;
        }
      }
      if (current.isNotEmpty) tokens.add(current);
      if (tokens.isEmpty) return null;

      // First pass: * and /
      List<String> pass1 = [];
      int i = 0;
      while (i < tokens.length) {
        if (tokens[i] == '*' || tokens[i] == '/') {
          final op = tokens[i];
          final prev = double.parse(pass1.removeLast());
          final next = double.parse(tokens[++i]);
          if (op == '*') {
            pass1.add((prev * next).toString());
          } else {
            if (next == 0) return double.nan;
            pass1.add((prev / next).toString());
          }
        } else {
          pass1.add(tokens[i]);
        }
        i++;
      }

      // Second pass: + and -
      double total = double.parse(pass1[0]);
      int j = 1;
      while (j < pass1.length) {
        final op = pass1[j];
        final next = double.parse(pass1[++j]);
        if (op == '+') {
          total += next;
        } else if (op == '-') {
          total -= next;
        }
        j++;
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  // ==========================================================
  // REUSABLE UI HELPERS
  // ==========================================================
  Widget _buildSectionCard({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _kInk,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildResultCard({
    required Color accentColor,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: _kMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.analytics_outlined,
                    size: 18, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildResultRow(
    String label,
    String value, {
    bool isHighlight = false,
    Color? highlightColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isHighlight ? 13 : 12,
                fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
                color: isHighlight ? _kInk : _kMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isHighlight ? 15 : 13,
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
              color: highlightColor ?? _kInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    String? prefixText,
    String? suffixText,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _kInk,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: _kMuted),
        prefixText: prefixText,
        prefixStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.bold, color: _kBlue),
        suffixText: suffixText,
        suffixStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: _kMuted),
        filled: true,
        fillColor: const Color(0xFFF9FAFD),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E4EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E4EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBlue, width: 1.5),
        ),
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildChoiceTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? _kBlue : const Color(0xFFF1F3F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : _kInk,
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChips({
    required List<double> presets,
    required double? currentVal,
    required ValueChanged<double> onSelect,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets.map((p) {
          final isSelected = currentVal == p;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              label: Text('${p.toInt()}%'),
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : _kInk,
              ),
              backgroundColor: isSelected ? _kBlue : const Color(0xFFF1F3F9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? _kBlue : Colors.transparent,
                ),
              ),
              onPressed: () => onSelect(p),
            ),
          );
        }).toList(),
      ),
    );
  }
}
