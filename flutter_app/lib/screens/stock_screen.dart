import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../widgets/shimmer.dart';

enum StockSort { stockLow, stockHigh, soldHigh, priceLow, priceHigh, nameAsc }

class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = 'All';
  String _statusFilter =
      'All'; // 'All', 'In Stock', 'Low Stock', 'Out of Stock'
  StockSort _sort = StockSort.stockLow;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<StockItem> get _filteredItems {
    final query = _searchCtrl.text.trim().toLowerCase();
    final all = JengaDB.instance.items;

    final filtered = all.where((item) {
      // Category filter
      if (_selectedCategory != 'All' && item.category != _selectedCategory) {
        return false;
      }
      // Status filter
      if (_statusFilter == 'In Stock' &&
          (item.isLowStock || item.isOutOfStock)) {
        return false;
      } else if ((_statusFilter == 'Half Sold' ||
              _statusFilter == 'Half Sold (50%+)') &&
          !item.isHalfSold) {
        return false;
      } else if (_statusFilter == 'Low Stock' && !item.isLowStock) {
        return false;
      } else if (_statusFilter == 'Out of Stock' && !item.isOutOfStock) {
        return false;
      }

      // Search query
      if (query.isNotEmpty) {
        final matchesName = item.name.toLowerCase().contains(query);
        final matchesSku = item.sku.toLowerCase().contains(query);
        final matchesCat = item.category.toLowerCase().contains(query);
        if (!matchesName && !matchesSku && !matchesCat) return false;
      }

      return true;
    }).toList();

    // Sort
    switch (_sort) {
      case StockSort.stockLow:
        filtered.sort((a, b) => a.stockRemaining.compareTo(b.stockRemaining));
        break;
      case StockSort.stockHigh:
        filtered.sort((a, b) => b.stockRemaining.compareTo(a.stockRemaining));
        break;
      case StockSort.soldHigh:
        filtered.sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
        break;
      case StockSort.priceLow:
        filtered.sort((a, b) => a.price.compareTo(b.price));
        break;
      case StockSort.priceHigh:
        filtered.sort((a, b) => b.price.compareTo(a.price));
        break;
      case StockSort.nameAsc:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
    }

    return filtered;
  }

  void _showSortSheet() {
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
                  const Text(
                    'Sort Items By',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              _sortTile(ctx, 'Stock: Low to High (Needs Restock)',
                  StockSort.stockLow),
              _sortTile(ctx, 'Stock: High to Low (Well Stocked)',
                  StockSort.stockHigh),
              _sortTile(ctx, 'Best Sellers (Units Sold)', StockSort.soldHigh),
              _sortTile(ctx, 'Price: Low to High', StockSort.priceLow),
              _sortTile(ctx, 'Price: High to Low', StockSort.priceHigh),
              _sortTile(ctx, 'Name: A to Z', StockSort.nameAsc),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sortTile(BuildContext ctx, String label, StockSort sortOption) {
    final active = _sort == sortOption;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: TextStyle(
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          color: active ? const Color(0xFF1E6BFF) : const Color(0xFF17162A),
        ),
      ),
      trailing: active
          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF1E6BFF))
          : null,
      onTap: () {
        setState(() => _sort = sortOption);
        Navigator.pop(ctx);
      },
    );
  }

  void _showAdjustStockDialog(StockItem item) {
    final ctrl = TextEditingController(text: item.stockRemaining.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Adjust Stock: ${item.name}',
            style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current remaining: ${item.stockRemaining} units'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'New Stock Quantity',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E6BFF)),
            onPressed: () async {
              final val = int.tryParse(ctrl.text);
              if (val != null) {
                await JengaDB.instance.setStock(item.id, val);
                setState(() {});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const kBg = Color(0xFFF8F8FF);
    const cardBg = Colors.white;
    const titleColor = Color(0xFF17162A);
    const kBlue = Color(0xFF1E6BFF);
    final allItems = JengaDB.instance.items;
    final totalSold = allItems.fold<int>(0, (sum, it) => sum + it.unitsSold);
    final lowStockCount =
        allItems.where((it) => it.isLowStock || it.isOutOfStock).length;
    final displayed = _filteredItems;

    final halfSoldCount = allItems.where((it) => it.isHalfSold).length;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: titleColor),
          onPressed: widget.onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stock & Inventory Manager',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: titleColor,
              ),
            ),
            Text(
              '${allItems.length} Total Products in Catalog',
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF777487)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort_rounded, color: kBlue),
            tooltip: 'Sort Items',
            onPressed: _showSortSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // GPS Location Supply Hub Dispatch Bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            color: const Color(0xFFEFF5FF),
            child: Row(
              children: [
                const Icon(Icons.near_me_rounded, size: 14, color: kBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Restock Dispatch: ${JengaDB.instance.nearestHubName} (${JengaDB.instance.nearestHubDistanceKm.toStringAsFixed(1)} km)',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kBlue),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // KPI Quick Stats
          Container(
            color: cardBg,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _statBadge(
                      'Total Items',
                      '${allItems.length}',
                      const Color(0xFFE8EEF8),
                      kBlue),
                  const SizedBox(width: 8),
                  _statBadge(
                      'Units Sold',
                      '$totalSold',
                      const Color(0xFFE1F6F4),
                      const Color(0xFF0F9D85)),
                  const SizedBox(width: 8),
                  _statBadge(
                      'Half Sold (50%+)',
                      '$halfSoldCount',
                      const Color(0xFFFEF3C7),
                      const Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  _statBadge(
                    'Low Stock',
                    '$lowStockCount',
                    const Color(0xFFFFF0DC),
                    const Color(0xFFE65100),
                  ),
                ],
              ),
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(
                        color: const Color(0xFFE4E6F0),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x06000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Color(0xFF17162A)),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: kBlue, size: 20),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        hintText: 'Search 500+ items or SKU...',
                        hintStyle: const TextStyle(
                            color: Color(0xFFB0ADC0),
                            fontSize: 13),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _showSortSheet,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EEF8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 18, color: kBlue),
                        SizedBox(width: 4),
                        Text(
                          'Sort',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Status Filter Tabs
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                'All',
                'In Stock',
                'Half Sold (50%+)',
                'Low Stock',
                'Out of Stock'
              ].map((st) {
                final active = _statusFilter == st;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(st),
                    selected: active,
                    onSelected: (_) => setState(() => _statusFilter = st),
                    backgroundColor: cardBg,
                    selectedColor: kBlue,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? Colors.white
                          : const Color(0xFF555268),
                    ),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: active
                            ? kBlue
                            : const Color(0xFFE4E6F0),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 6),

          // Category Pills
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: JengaDB.instance.getCategories().map((cat) {
                final active = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: active,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    selectedColor: const Color(0xFF0F172A),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : const Color(0xFF706C81),
                    ),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: active
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFE4E6F0),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 6),

          // List Header info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${displayed.length} of ${allItems.length} items',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF706C81)),
                ),
                Text(
                  _sortLabel,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: kBlue),
                ),
              ],
            ),
          ),

          // Product Items List
          Expanded(
            child: displayed.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined,
                            size: 54, color: Color(0xFFB0ADC0)),
                        const SizedBox(height: 12),
                        const Text(
                          'No items match your filter',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        TextButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _selectedCategory = 'All';
                              _statusFilter = 'All';
                            });
                          },
                          child: const Text('Reset Filters'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: displayed.length,
                    itemBuilder: (ctx, idx) {
                      final item = displayed[idx];
                      return _buildItemCard(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String get _sortLabel {
    switch (_sort) {
      case StockSort.stockLow:
        return 'Sorted: Low Stock first';
      case StockSort.stockHigh:
        return 'Sorted: High Stock first';
      case StockSort.soldHigh:
        return 'Sorted: Top Sellers';
      case StockSort.priceLow:
        return 'Sorted: Price Low to High';
      case StockSort.priceHigh:
        return 'Sorted: Price High to Low';
      case StockSort.nameAsc:
        return 'Sorted: Name A-Z';
    }
  }

  Widget _statBadge(String label, String value, Color bg, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: fg.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, color: fg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(StockItem item) {
    const cardBg = Colors.white;
    const defaultBorder = Color(0xFFECEEF5);
    Color statusColor;
    String statusText;
    if (item.isOutOfStock) {
      statusColor = const Color(0xFFD32F2F);
      statusText = 'Out of Stock (0)';
    } else if (item.isLowStock) {
      statusColor = const Color(0xFFE65100);
      statusText = 'Low Stock (${item.stockRemaining} left)';
    } else {
      statusColor = const Color(0xFF2E7D32);
      statusText = 'In Stock (${item.stockRemaining})';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isLowStock
              ? const Color(0xFFFFD180)
              : (item.isOutOfStock ? const Color(0xFFFFCDD2) : defaultBorder),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Real Product Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 70,
              height: 70,
              child: Image.network(
                item.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFE8EEF8),
                  child: const Icon(Icons.image_outlined,
                      color: Color(0xFF1E6BFF), size: 28),
                ),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const ShimmerBox(
                      width: 70, height: 70, borderRadius: 12);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: Color(0xFF17162A),
                        ),
                      ),
                    ),
                    Text(
                      'KES ${item.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E6BFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      item.sku,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF908D9F),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• ${item.category}',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF908D9F)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Stock badge & Half Sold alert badge
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                        ),
                        if (item.isHalfSold)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                              border:
                                  Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Text(
                              '${item.soldPercentage}% Sold',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      'Sold: ${item.unitsSold}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF706C81),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Quick Stock adjuster
          const SizedBox(width: 6),
          Column(
            children: [
              _circleBtn(Icons.add_rounded, const Color(0xFF1E6BFF), () async {
                await JengaDB.instance.adjustStock(item.id, 1);
                setState(() {});
              }),
              const SizedBox(height: 4),
              _circleBtn(Icons.edit_outlined, const Color(0xFF706C81), () {
                _showAdjustStockDialog(item);
              }),
              const SizedBox(height: 4),
              _circleBtn(Icons.remove_rounded, const Color(0xFFE65100),
                  () async {
                await JengaDB.instance.adjustStock(item.id, -1);
                setState(() {});
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color col, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: col.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: col),
      ),
    );
  }
}
