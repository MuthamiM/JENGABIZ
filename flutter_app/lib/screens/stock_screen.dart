import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/inventory_pdf_export_service.dart';
import '../services/stock_notification_service.dart';
import '../widgets/cached_stock_image.dart';
import '../widgets/product_editor_dialog.dart';

enum StockSort { stockLow, stockHigh, soldHigh, priceLow, priceHigh, nameAsc }

class StockScreen extends StatefulWidget {
  const StockScreen({
    super.key,
    required this.onBack,
    this.focusItemId,
    this.initialStatusFilter,
  });
  final VoidCallback onBack;
  final String? focusItemId;
  final String? initialStatusFilter;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = 'All';
  String _statusFilter =
      'All'; // 'All', 'In Stock', 'Low Stock', 'Out of Stock'
  StockSort _sort = StockSort.stockLow;
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    _applyInitialFocus();
    _syncInventoryOnOpen();
  }

  void _applyInitialFocus() {
    if (widget.initialStatusFilter != null &&
        const {
          'All',
          'In Stock',
          'Half Sold (50%+)',
          'Low Stock',
          'Out of Stock',
        }.contains(widget.initialStatusFilter)) {
      _statusFilter = widget.initialStatusFilter!;
    }
    if (widget.focusItemId != null) {
      final matching =
          JengaDB.instance.items.where((it) => it.id == widget.focusItemId);
      if (matching.isNotEmpty) {
        _statusFilter = 'All';
        _selectedCategory = 'All';
        _searchCtrl.text = matching.first.name;
      }
    }
  }

  Future<void> _syncInventoryOnOpen() async {
    try {
      final synced = await JengaDB.instance.syncStockWithServer();
      if (mounted && synced) {
        if (widget.focusItemId != null && _searchCtrl.text.isEmpty) {
          _applyInitialFocus();
        }
        setState(() {});
      }
    } catch (_) {
      // Keep the cached inventory visible and retry on the next app resume.
    }
  }

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

    if (widget.focusItemId != null) {
      final focusIdx =
          filtered.indexWhere((item) => item.id == widget.focusItemId);
      if (focusIdx > 0) {
        final focused = filtered.removeAt(focusIdx);
        filtered.insert(0, focused);
      }
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

  Future<void> _showProductEditor({StockItem? item}) async {
    final categories = JengaDB.instance.items
        .map((stockItem) => stockItem.category)
        .toSet()
        .toList();
    final saved = await showDialog<StockItem>(
      context: context,
      builder: (_) => ProductEditorDialog(
        categories: categories,
        item: item,
      ),
    );
    if (saved == null) return;

    final persisted = await JengaDB.instance.saveStockItem(saved);
    if (!mounted) return;
    if (!persisted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not save this product. Please try again.')),
      );
      return;
    }
    await StockNotificationService.instance.notifyStockLevel(
      itemId: saved.id,
      itemName: saved.name,
      remaining: saved.stockRemaining,
      reorderLevel: saved.reorderLevel,
      previousRemaining: item?.stockRemaining,
    );
    if (!mounted) return;
    setState(() {
      _selectedCategory = 'All';
      _statusFilter = 'All';
      _searchCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(item == null
            ? 'Product saved. Stock will sync when you are online.'
            : 'Product updated. Stock will sync when you are online.'),
      ),
    );
  }

  Future<void> _confirmDelete(StockItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove product?'),
        content: Text('${item.name} will be removed from this shop inventory.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final persisted = await JengaDB.instance.deleteStockItem(item.id);
    if (!mounted) return;
    if (!persisted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not remove this product. Please try again.')),
      );
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product removed from inventory.')),
    );
  }

  Future<void> _changeStock(StockItem item, int delta) async {
    final previousRemaining = item.stockRemaining;
    final previousUnitsSold = item.unitsSold;
    final saved = await JengaDB.instance.adjustStock(item.id, delta);
    if (!mounted) return;
    setState(() {});
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not save the stock change. Please retry.')),
      );
      return;
    }
    await StockNotificationService.instance.notifyStockLevel(
      itemId: item.id,
      itemName: item.name,
      remaining: item.stockRemaining,
      reorderLevel: item.reorderLevel,
      previousRemaining: previousRemaining,
    );
    if (delta < 0) {
      await StockNotificationService.instance.notifyHalfSold(
        itemId: item.id,
        itemName: item.name,
        previousRemaining: previousRemaining,
        previousUnitsSold: previousUnitsSold,
        remaining: item.stockRemaining,
        unitsSold: item.unitsSold,
      );
    }
  }

  Future<void> _exportStockPdf() async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    final messenger = ScaffoldMessenger.of(context);
    final db = JengaDB.instance;
    final revenue = db.items
        .fold<double>(0, (sum, item) => sum + item.price * item.unitsSold);
    final cost = db.items
        .fold<double>(0, (sum, item) => sum + item.costPrice * item.unitsSold);
    final units = db.items.fold<int>(0, (sum, item) => sum + item.unitsSold);
    try {
      await InventoryPdfExportService.shareInventory(
        items: db.items,
        shopName: db.currentUser?.shopName ?? 'JengaBiz shop',
        revenue: revenue,
        cost: cost,
        unitsSold: units,
        ownerId: db.currentUser?.id ?? db.inventoryOwnerId,
      );
    } catch (_) {
      if (!mounted || !messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Could not export the stock PDF. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const kBg = Color(0xFFF8F8FF);
    const cardBg = Colors.white;
    const titleColor = Color(0xFF17162A);
    const kBlue = Color(0xFF1E6BFF);
    final allItems = JengaDB.instance.items;
    final displayed = _filteredItems;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: titleColor),
          onPressed: widget.onBack,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: kBlue),
            tooltip: 'Export stock PDF',
            onPressed: _exportStockPdf,
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: kBlue),
            tooltip: 'Add product',
            onPressed: () => _showProductEditor(),
          ),
          IconButton(
            icon: const Icon(Icons.sort_rounded, color: kBlue),
            tooltip: 'Sort Items',
            onPressed: _showSortSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Keep the search field fixed while the inventory content scrolls.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE4E6F0)),
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
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: kBlue, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  hintText: 'Search product name, category, or SKU...',
                  hintStyle:
                      const TextStyle(color: Color(0xFFB0ADC0), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _statusFilters()),
                SliverToBoxAdapter(child: _categoryFilters()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Showing ${displayed.length} of ${allItems.length} items',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF706C81),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _sortLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '+ restocks one unit  ·  − records one sale  ·  edit changes product details',
                        style:
                            TextStyle(fontSize: 10, color: Color(0xFF706C81)),
                      ),
                    ),
                  ),
                ),
                if (displayed.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyState(allItems.isEmpty),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildItemCard(displayed[index]),
                        childCount: displayed.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add product'),
      ),
    );
  }

  Widget _statusFilters() {
    const blue = Color(0xFF1E6BFF);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          'All',
          'In Stock',
          'Half Sold (50%+)',
          'Low Stock',
          'Out of Stock',
        ].map((status) {
          final active = _statusFilter == status;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(status),
              selected: active,
              onSelected: (_) => setState(() => _statusFilter = status),
              backgroundColor: Colors.white,
              selectedColor: blue,
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xFF555268),
              ),
              shape: StadiumBorder(
                side: BorderSide(
                  color: active ? blue : const Color(0xFFE4E6F0),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _categoryFilters() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        children: JengaDB.instance.getCategories().map((category) {
          final active = _selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(category),
              selected: active,
              onSelected: (_) => setState(() => _selectedCategory = category),
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
    );
  }

  Widget _emptyState(bool inventoryIsEmpty) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 54, color: Color(0xFFB0ADC0)),
          const SizedBox(height: 12),
          const Text(
            'No products in this view',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          if (inventoryIsEmpty)
            FilledButton.icon(
              onPressed: () => _showProductEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add your first product'),
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

  Widget _buildItemCard(StockItem item) {
    const blue = Color(0xFF1E6BFF);
    const defaultBorder = Color(0xFFE7EAF2);
    Color statusColor;
    String statusText;
    if (item.isOutOfStock) {
      statusColor = const Color(0xFFD32F2F);
      statusText = 'OUT OF STOCK';
    } else if (item.isLowStock) {
      statusColor = const Color(0xFFE65100);
      statusText = 'LOW STOCK';
    } else {
      statusColor = const Color(0xFF2E7D32);
      statusText = 'IN STOCK';
    }

    final isFocused =
        widget.focusItemId != null && item.id == widget.focusItemId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          width: isFocused ? 1.8 : 1.0,
          color: isFocused
              ? blue
              : item.isLowStock
                  ? const Color(0xFFFFD180)
                  : (item.isOutOfStock
                      ? const Color(0xFFFFCDD2)
                      : defaultBorder),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child:
                    SizedBox(width: 58, height: 58, child: _stockPhoto(item)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF17162A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'KES ${item.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: blue,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [if (item.sku.isNotEmpty) item.sku, item.category]
                          .join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF908D9F),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Product actions',
                icon: const Icon(Icons.more_vert_rounded,
                    color: Color(0xFF747186)),
                onSelected: (action) {
                  if (action == 'edit') {
                    _showProductEditor(item: item);
                  } else if (action == 'remove') {
                    _confirmDelete(item);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 19),
                      SizedBox(width: 10),
                      Text('Edit product'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 19, color: Color(0xFFD32F2F)),
                      SizedBox(width: 10),
                      Text('Remove product'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Divider(height: 1, color: Color(0xFFECEEF5)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.35,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${item.unitsSold} sold${item.isHalfSold ? '  ·  ${item.soldPercentage}% moved' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF706C81),
                      ),
                    ),
                  ],
                ),
              ),
              _stockAdjustButton(
                Icons.remove_rounded,
                const Color(0xFFE65100),
                () => _changeStock(item, -1),
                tooltip: 'Record one sale',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${item.stockRemaining}',
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF17162A),
                      ),
                    ),
                    const Text(
                      'LEFT',
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF908D9F),
                      ),
                    ),
                  ],
                ),
              ),
              _stockAdjustButton(
                Icons.add_rounded,
                blue,
                () => _changeStock(item, 1),
                tooltip: 'Restock one unit',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stockPhoto(StockItem item) => CachedStockImage(
        imageUrl: item.imageUrl,
        ownerId: JengaDB.instance.currentUser?.id ??
            JengaDB.instance.inventoryOwnerId,
      );

  Widget _stockAdjustButton(IconData icon, Color col, VoidCallback onTap,
      {required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: col.withValues(alpha: 0.10),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 20, color: col),
          ),
        ),
      ),
    );
  }
}
