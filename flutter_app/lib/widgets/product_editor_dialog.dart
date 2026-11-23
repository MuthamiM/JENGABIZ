import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/db_service.dart';
import 'cached_stock_image.dart';

class ProductEditorDialog extends StatefulWidget {
  const ProductEditorDialog({
    super.key,
    required this.categories,
    this.item,
  });

  final List<String> categories;
  final StockItem? item;

  @override
  State<ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<ProductEditorDialog> {
  static const _addCategoryValue = '__add_category__';
  static const _maxImageBytes = 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _quantity = TextEditingController();
  final _reorder = TextEditingController();
  final _imagePicker = ImagePicker();

  late final List<String> _categories;
  late String _category;
  late String _imageUrl;
  bool _choosingImage = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name.text = item?.name ?? '';
    _sku.text = item?.sku ?? '';
    _price.text = item?.price.toString() ?? '';
    _cost.text = item?.costPrice.toString() ?? '';
    _quantity.text = item?.stockRemaining.toString() ?? '0';
    _reorder.text = item?.reorderLevel.toString() ?? '10';
    _category =
        item?.category.trim().isNotEmpty == true ? item!.category : 'General';
    _imageUrl = item?.imageUrl ?? '';
    _categories = {
      'General',
      'Grocery',
      'Beverages',
      'Household',
      'Personal care',
      'Electronics',
      'Clothing',
      ...widget.categories
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
      _category,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _cost.dispose();
    _quantity.dispose();
    _reorder.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_choosingImage) return;
    setState(() => _choosingImage = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 68,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty || bytes.length > _maxImageBytes) {
        _showMessage('Choose a photo under 1 MB and try again.');
        return;
      }
      final mimeType = _mimeType(picked);
      if (mimeType == null) {
        _showMessage('Choose a JPEG, PNG, or WebP photo.');
        return;
      }
      setState(
          () => _imageUrl = 'data:$mimeType;base64,${base64Encode(bytes)}');
    } catch (_) {
      if (mounted) _showMessage('Could not open the photo picker. Try again.');
    } finally {
      if (mounted) setState(() => _choosingImage = false);
    }
  }

  String? _mimeType(XFile image) {
    final mime = image.mimeType?.toLowerCase();
    if (const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
      return mime;
    }
    final name = image.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addCategory() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _AddCategoryDialog(),
    );
    if (!mounted || value == null || value.trim().isEmpty) return;
    final category = value.trim();
    setState(() {
      if (!_categories.any(
          (existing) => existing.toLowerCase() == category.toLowerCase())) {
        _categories.add(category);
        _categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }
      _category = category;
    });
  }

  Widget _categoryField() => DropdownButtonFormField<String>(
        value: _category,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Category',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          ..._categories.map(
            (category) => DropdownMenuItem(
              value: category,
              child: Text(category, overflow: TextOverflow.ellipsis),
            ),
          ),
          const DropdownMenuItem(
            value: _addCategoryValue,
            child: Text('＋ Add a category'),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          if (value == _addCategoryValue) {
            _addCategory();
          } else {
            setState(() => _category = value);
          }
        },
      );

  Widget _imagePreview() {
    const placeholder =
        Icon(Icons.inventory_2_outlined, color: Color(0xFF1E6BFF));
    final url = _imageUrl;
    if (url.startsWith('data:image/')) {
      final comma = url.indexOf(',');
      if (comma > 0) {
        try {
          return Image.memory(
            base64Decode(url.substring(comma + 1)),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          );
        } catch (_) {
          return placeholder;
        }
      }
    } else if (url.startsWith('stock-image:')) {
      return CachedStockImage(
        imageUrl: url,
        ownerId: JengaDB.instance.currentUser?.id ??
            JengaDB.instance.inventoryOwnerId,
        width: 64,
        height: 64,
      );
    } else if (url.startsWith('https://') || url.startsWith('http://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return placeholder;
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
    bool required = false,
    bool integer = false,
    bool decimal = false,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: (raw) {
          final value = raw?.trim() ?? '';
          if (required && value.isEmpty) return 'Required';
          if (integer &&
              (int.tryParse(value) == null || int.parse(value) < 0)) {
            return 'Enter a whole number 0 or greater';
          }
          if (decimal &&
              (double.tryParse(value) == null ||
                  !double.parse(value).isFinite ||
                  double.parse(value) < 0)) {
            return 'Enter an amount 0 or greater';
          }
          return null;
        },
      );

  StockItem _buildItem() => StockItem(
        id: widget.item?.id ?? 'item_${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        category: _category,
        price: double.parse(_price.text.trim()),
        costPrice: double.parse(_cost.text.trim()),
        stockRemaining: int.parse(_quantity.text.trim()),
        unitsSold: widget.item?.unitsSold ?? 0,
        sku: _sku.text.trim(),
        imageUrl: _imageUrl,
        reorderLevel: int.parse(_reorder.text.trim()),
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final contentHeight = math.max(
      180.0,
      media.size.height - media.viewInsets.bottom - 250,
    );
    final item = widget.item;

    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(item == null ? 'Add Product' : 'Edit Product'),
      content: SizedBox(
        width: math.min(420.0, media.size.width - 72),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: contentHeight),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(_name, 'Product name', required: true),
                  const SizedBox(height: 10),
                  _categoryField(),
                  const SizedBox(height: 10),
                  _field(_sku, 'SKU / barcode (optional)'),
                  const SizedBox(height: 10),
                  _field(
                    _price,
                    'Selling price (KES)',
                    required: true,
                    decimal: true,
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                  _field(
                    _cost,
                    'Buying cost (KES)',
                    required: true,
                    decimal: true,
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                  _field(
                    _quantity,
                    'Quantity on hand',
                    required: true,
                    integer: true,
                    keyboard: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    _reorder,
                    'Low-stock alert at',
                    required: true,
                    integer: true,
                    keyboard: TextInputType.number,
                  ),
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 64,
                                height: 64,
                                color: const Color(0xFFE8EEF8),
                                alignment: Alignment.center,
                                child: _imagePreview(),
                              ),
                            ),
                            if (_imageUrl.isNotEmpty)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 28,
                                    height: 28,
                                  ),
                                  tooltip: 'Remove image',
                                  onPressed: () =>
                                      setState(() => _imageUrl = ''),
                                  icon:
                                      const Icon(Icons.close_rounded, size: 16),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _choosingImage ? null : _pickImage,
                        icon: _choosingImage
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(_imageUrl.isEmpty
                            ? 'Upload stock image'
                            : 'Change image'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'JPEG, PNG or WebP · up to 1 MB · only the photo you select is shared',
                      style: TextStyle(fontSize: 11, color: Color(0xFF777487)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style:
              FilledButton.styleFrom(backgroundColor: const Color(0xFF1E6BFF)),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(context, _buildItem());
          },
          child: Text(item == null ? 'Add to Inventory' : 'Save Product'),
        ),
      ],
    );
  }
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add a category'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 100,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final category = _controller.text.trim();
              if (category.isNotEmpty) Navigator.pop(context, category);
            },
            child: const Text('Add'),
          ),
        ],
      );
}
