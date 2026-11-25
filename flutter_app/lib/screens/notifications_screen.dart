import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/db_service.dart';
import '../services/notification_center_service.dart';
import '../services/stock_notification_service.dart';

/// Full-screen notifications list with expandable cards, deep-link support,
/// and contextual actions.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.onBack,
    required this.onAction,
    this.expandNotificationId,
    this.openRequestSeq = 0,
  });

  final VoidCallback onBack;
  final void Function(NotificationAction action) onAction;

  /// If set, auto-expands this notification on open (e.g. from a push tap).
  final String? expandNotificationId;

  /// Monotonically increasing sequence from notification tap events so
  /// tapping a second push while already on this screen still expands it.
  final int openRequestSeq;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'All';
  final Set<String> _expanded = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    NotificationCenterService.instance.addListener(_onStoreChanged);
    unawaited(_initNotifications());
  }

  @override
  void didUpdateWidget(covariant NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expandNotificationId != null &&
        (widget.expandNotificationId != oldWidget.expandNotificationId ||
            widget.openRequestSeq != oldWidget.openRequestSeq)) {
      _activateDeepLinkTarget(widget.expandNotificationId!);
    }
  }

  @override
  void dispose() {
    NotificationCenterService.instance.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initNotifications() async {
    await NotificationCenterService.instance.ensureInitialized();
    if (!mounted) return;
    if (widget.expandNotificationId != null) {
      await _activateDeepLinkTarget(widget.expandNotificationId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _activateDeepLinkTarget(String id) async {
    _filter = 'All';
    _expanded.add(id);
    await NotificationCenterService.instance.markAsRead(id);
    if (mounted) setState(() {});
  }

  Future<void> _toggleExpanded(JengaNotification item) async {
    setState(() {
      if (_expanded.contains(item.id)) {
        _expanded.remove(item.id);
      } else {
        _expanded.add(item.id);
      }
    });
    if (!item.isRead) {
      await NotificationCenterService.instance.markAsRead(item.id);
    }
  }

  Future<void> _markAllAsRead() async {
    await NotificationCenterService.instance.markAllAsRead();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _handleAction(
    JengaNotification notification,
    NotificationAction action,
  ) async {
    if (!notification.isRead) {
      await NotificationCenterService.instance.markAsRead(notification.id);
    }

    if (action.iconKey == 'restock' && action.itemId != null) {
      final matching =
          JengaDB.instance.items.where((it) => it.id == action.itemId);
      if (matching.isNotEmpty) {
        final restocked = await _showQuickRestockDialog(matching.first);
        if (restocked == true) return;
        // User tapped "View in Stock" inside dialog or cancelled restock.
      }
    }

    if (action.url != null) {
      final uri = Uri.tryParse(action.url!);
      if (uri != null && uri.scheme.toLowerCase() == 'https') {
        try {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return;
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this notification link.')),
      );
      return;
    }

    widget.onAction(action);
  }

  Future<bool?> _showQuickRestockDialog(StockItem item) async {
    final qtyCtrl = TextEditingController(text: '10');
    var saving = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> applyRestock(int delta) async {
            if (saving || delta <= 0) return;
            setDialogState(() => saving = true);
            final previousRemaining = item.stockRemaining;
            final saved = await JengaDB.instance.adjustStock(item.id, delta);
            if (!ctx.mounted) return;
            if (saved) {
              unawaited(StockNotificationService.instance.notifyStockLevel(
                itemId: item.id,
                itemName: item.name,
                remaining: item.stockRemaining,
                reorderLevel: item.reorderLevel,
                previousRemaining: previousRemaining,
              ));
              Navigator.pop(ctx, true);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Added $delta units to ${item.name} (${item.stockRemaining} now in stock).',
                    ),
                  ),
                );
                setState(() {});
              }
            } else {
              setDialogState(() => saving = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not save restock. Please try again.'),
                  ),
                );
              }
            }
          }

          return AlertDialog(
            title: Text(
              'Restock ${item.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Currently ${item.stockRemaining} left · Alert level ${item.reorderLevel}',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF777487)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [5, 10, 20, 50]
                      .map((preset) => ActionChip(
                            label: Text('+$preset'),
                            onPressed: saving
                                ? null
                                : () => qtyCtrl.text = '$preset',
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Units to add',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () {
                        Navigator.pop(ctx, false);
                        widget.onAction(NotificationAction(
                          label: 'View in Stock',
                          iconKey: 'stock',
                          route: 'stock',
                          itemId: item.id,
                        ));
                      },
                child: const Text('Open in Stock'),
              ),
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () {
                        final parsed = int.tryParse(qtyCtrl.text.trim());
                        if (parsed != null && parsed > 0) {
                          unawaited(applyRestock(parsed));
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add stock'),
              ),
            ],
          );
        },
      ),
    );
    qtyCtrl.dispose();
    return result;
  }

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.stock:
        return Icons.warning_amber_rounded;
      case NotificationType.sales:
        return Icons.trending_up_rounded;
      case NotificationType.referral:
        return Icons.card_giftcard_rounded;
      case NotificationType.security:
        return Icons.fingerprint_rounded;
      case NotificationType.location:
        return Icons.my_location_rounded;
      case NotificationType.sync:
        return Icons.sync_rounded;
      case NotificationType.push:
        return Icons.notifications_active_rounded;
      case NotificationType.update:
        return Icons.system_update_alt_rounded;
    }
  }

  IconData _iconForActionKey(String iconKey) {
    switch (iconKey) {
      case 'restock':
        return Icons.add_shopping_cart_rounded;
      case 'stock':
        return Icons.inventory_2_outlined;
      case 'analytics':
        return Icons.bar_chart_rounded;
      case 'profile':
        return Icons.person_outline_rounded;
      case 'update':
        return Icons.system_update_alt_rounded;
      case 'link':
        return Icons.open_in_new_rounded;
      default:
        return Icons.arrow_forward_rounded;
    }
  }

  Color _colorForType(NotificationType type) {
    switch (type) {
      case NotificationType.stock:
        return const Color(0xFFEF4444);
      case NotificationType.sales:
        return const Color(0xFF10B981);
      case NotificationType.referral:
        return const Color(0xFF8B5CF6);
      case NotificationType.security:
        return const Color(0xFF1E6BFF);
      case NotificationType.location:
        return const Color(0xFFF59E0B);
      case NotificationType.sync:
        return const Color(0xFF06B6D4);
      case NotificationType.push:
        return const Color(0xFF1E6BFF);
      case NotificationType.update:
        return const Color(0xFF1E6BFF);
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  String _formattedTimestamp(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, ${local.year} · $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    const kBg = Color(0xFFF8F8FF);
    const titleColor = Color(0xFF17162A);
    const kBlue = Color(0xFF1E6BFF);

    final all = NotificationCenterService.instance.notifications;
    final stockAlertsCount =
        all.where((n) => n.type == NotificationType.stock).length;
    final unreadCount = all.where((n) => !n.isRead).length;
    final pushCount = all.where((n) => n.isPush).length;

    final filtered = all.where((n) {
      if (_filter == 'Unread') return !n.isRead;
      if (_filter == 'Stock Alerts' || _filter == 'Alerts') {
        return n.type == NotificationType.stock;
      }
      if (_filter == 'Push') return n.isPush;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon:
                        const Icon(Icons.arrow_back_rounded, color: titleColor),
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    TextButton(
                      onPressed: _markAllAsRead,
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(
                          color: kBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Filter Tabs
            if (all.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('All', _filter == 'All'),
                        if (unreadCount > 0 || _filter == 'Unread') ...[
                          const SizedBox(width: 8),
                          _filterChip('Unread', _filter == 'Unread',
                              badge: unreadCount),
                        ],
                        if (stockAlertsCount > 0 ||
                            _filter == 'Stock Alerts') ...[
                          const SizedBox(width: 8),
                          _filterChip(
                            'Stock Alerts',
                            _filter == 'Stock Alerts' || _filter == 'Alerts',
                            badge: stockAlertsCount,
                          ),
                        ],
                        if (pushCount > 0 || _filter == 'Push') ...[
                          const SizedBox(width: 8),
                          _filterChip('Push', _filter == 'Push',
                              badge: pushCount),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Notifications List
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: 56,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No new notifications',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4A475C),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Low stock alerts and push updates will appear here when they arrive.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF777487),
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, idx) =>
                              _notificationCard(filtered[idx]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a single expandable notification card.
  Widget _notificationCard(JengaNotification item) {
    const kBlue = Color(0xFF1E6BFF);
    const itemTitleColor = Color(0xFF17162A);
    const itemBodyColor = Color(0xFF6B687D);
    final color = _colorForType(item.type);
    final isExpanded = _expanded.contains(item.id);
    final cardBg = item.isRead ? Colors.white : const Color(0xFFF1F5FD);

    final matchingItems = item.itemId == null
        ? const <StockItem>[]
        : JengaDB.instance.items.where((it) => it.id == item.itemId).toList();
    final linkedItem = matchingItems.isNotEmpty ? matchingItems.first : null;

    // Build actions strictly from what the notification has.
    final effectiveActions = List<NotificationAction>.from(item.actions);
    if (effectiveActions.isEmpty && item.route != null) {
      effectiveActions.add(NotificationAction(
        label: item.route == 'stock' ? 'Open Stock' : 'Open',
        iconKey: item.route!,
        route: item.route,
        itemId: item.itemId,
      ));
    }
    // When linked to an existing StockItem, also allow viewing it directly
    // alongside quick restock if not already provided.
    if (linkedItem != null &&
        effectiveActions.length == 1 &&
        effectiveActions.first.iconKey == 'restock') {
      effectiveActions.add(NotificationAction(
        label: 'View in Stock',
        iconKey: 'stock',
        route: 'stock',
        itemId: linkedItem.id,
      ));
    }

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      elevation: item.isRead ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => unawaited(_toggleExpanded(item)),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_iconForType(item.type),
                          color: color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: item.isRead
                                        ? FontWeight.w700
                                        : FontWeight.w800,
                                    color: itemTitleColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _timeAgo(item.timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (!isExpanded && item.body.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: itemBodyColor,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!item.isRead) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: kBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey.shade400,
                      size: 22,
                    ),
                  ],
                ),

                if (isExpanded) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 58),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.body.isNotEmpty)
                          Text(
                            item.body,
                            style: const TextStyle(
                              fontSize: 13,
                              color: itemBodyColor,
                              height: 1.5,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _formattedTimestamp(item.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.isPush)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: kBlue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Push',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: kBlue,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (linkedItem != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F7FB),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFE4E6F0)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${linkedItem.name} · ${linkedItem.stockRemaining} left (Alert at ${linkedItem.reorderLevel})',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: itemTitleColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (effectiveActions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: effectiveActions
                                .map((action) =>
                                    _actionButton(item, action, color))
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => unawaited(
                              NotificationCenterService.instance
                                  .removeNotification(item.id),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 15),
                            label: const Text(
                              'Dismiss',
                              style: TextStyle(fontSize: 11),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey.shade500,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renders an actionable pill button inside an expanded notification.
  Widget _actionButton(
    JengaNotification notification,
    NotificationAction action,
    Color accentColor,
  ) {
    return Material(
      color: accentColor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => unawaited(_handleAction(notification, action)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconForActionKey(action.iconKey),
                  size: 15, color: accentColor),
              const SizedBox(width: 6),
              Text(
                action.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String title, bool active, {int? badge}) {
    const kBlue = Color(0xFF1E6BFF);
    final chipBg = active ? kBlue : Colors.white;
    final chipBorder = active ? kBlue : const Color(0xFFE2E4EC);
    final chipTextColor = active ? Colors.white : const Color(0xFF4A475C);

    return GestureDetector(
      onTap: () => setState(() => _filter = title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chipBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: chipTextColor,
              ),
            ),
            if (badge != null && badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? Colors.white : kBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: active ? kBlue : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
