import 'package:flutter/material.dart';
import '../services/db_service.dart';

enum NotificationType { stock, sales, referral, security, location, sync }

class JengaNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final NotificationType type;
  bool isRead;
  final String? route;

  JengaNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.type,
    this.isRead = false,
    this.route,
  });
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.onBack,
    required this.onNavigate,
  });

  final VoidCallback onBack;
  final void Function(String route) onNavigate;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'All'; // 'All', 'Unread', 'Alerts'
  late List<JengaNotification> _notifications;

  @override
  void initState() {
    super.initState();
    _buildNotifications();
  }

  void _buildNotifications() {
    final items = JengaDB.instance.items;
    final lowStockCount =
        items.where((i) => i.isLowStock || i.isOutOfStock).length;
    final halfSoldItems = items.where((i) => i.isHalfSold).toList()
      ..sort((a, b) => b.soldRatio.compareTo(a.soldRatio));
    final totalSold = items.fold(0, (acc, i) => acc + i.unitsSold);
    final totalRev =
        items.fold<double>(0.0, (acc, i) => acc + (i.unitsSold * i.price));
    final hubName = JengaDB.instance.nearestHubName;
    final hubDist = JengaDB.instance.nearestHubDistanceKm;

    final notifs = <JengaNotification>[];

    // 1. Prominent Half-Sold Stock Milestone Alert
    if (halfSoldItems.isNotEmpty) {
      notifs.add(
        JengaNotification(
          id: 'half_sold_milestone',
          title: 'Stock Alert: ${halfSoldItems.length} Products 50%+ Sold',
          body:
              '${halfSoldItems.length} items have crossed the half-sold threshold. Restock recommended from $hubName ($hubDist km away).',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          type: NotificationType.stock,
          isRead: false,
          route: 'stock',
        ),
      );
    }

    // 2. Individual Stock Notifications for ALL Items When Half Sold
    for (int idx = 0; idx < halfSoldItems.length; idx++) {
      final it = halfSoldItems[idx];
      notifs.add(
        JengaNotification(
          id: 'half_sold_${it.id}',
          title: '${it.name} • 50%+ Sold (${it.soldPercentage}%)',
          body:
              '${it.unitsSold} of ${it.totalStock} units sold (${it.soldPercentage}%). ${it.stockRemaining} units remaining in shop. Reorder level: ${it.reorderLevel}.',
          timestamp: DateTime.now().subtract(Duration(minutes: 12 + (idx * 4))),
          type: NotificationType.stock,
          isRead: idx > 4, // top alerts unread
          route: 'stock',
        ),
      );
    }

    // 3. Low stock threshold alert
    if (lowStockCount > 0) {
      notifs.add(
        JengaNotification(
          id: 'low_stock_summary',
          title: 'Critical Safety Restock: $lowStockCount Items Low',
          body:
              '$lowStockCount products have fallen below minimum safety levels. Tap to review items in inventory.',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
          type: NotificationType.stock,
          isRead: false,
          route: 'stock',
        ),
      );
    }

    // 4. Revenue milestone
    notifs.add(
      JengaNotification(
        id: 'revenue_milestone',
        title:
            'Revenue Milestone: KES ${totalRev.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
        body:
            'Your business has recorded $totalSold total units sold across catalog items.',
        timestamp: DateTime.now().subtract(const Duration(hours: 6)),
        type: NotificationType.sales,
        isRead: true,
        route: 'analytics',
      ),
    );

    // 6. Security / Biometrics
    notifs.add(
      JengaNotification(
        id: 'security_biometric',
        title: 'Biometric Security Active',
        body:
            'Protect your daily cash flow and inventory counts with Face ID or fingerprint authentication.',
        timestamp: DateTime.now().subtract(const Duration(hours: 14)),
        type: NotificationType.security,
        isRead: true,
        route: 'profile',
      ),
    );

    // 7. Active GPS Shop Location & Logistics Hub
    notifs.add(
      JengaNotification(
        id: 'location_hub',
        title: 'GPS Location Active: $hubName',
        body:
            'Shop location synced with nearest hub ($hubName, $hubDist km away) for express restock logistics.',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        type: NotificationType.location,
        isRead: true,
        route: 'stock',
      ),
    );

    // 8. Redis Cache Sync
    notifs.add(
      JengaNotification(
        id: 'sync_cache',
        title: 'Redis Cache Synchronization',
        body:
            'Multi-tier cache and local shop records synchronized with central API service.',
        timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 4)),
        type: NotificationType.sync,
        isRead: true,
        route: 'stock',
      ),
    );

    _notifications = notifs;
  }

  void _markAllAsRead() {
    setState(() {
      for (final n in _notifications) {
        n.isRead = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All notifications marked as read'),
        duration: Duration(seconds: 2),
      ),
    );
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
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    const kBg = Color(0xFFF8F8FF);
    const titleColor = Color(0xFF17162A);
    const kBlue = Color(0xFF1E6BFF);

    final stockAlertsCount =
        _notifications.where((n) => n.type == NotificationType.stock).length;
    final unreadCount = _notifications.where((n) => !n.isRead).length;

    final filtered = _notifications.where((n) {
      if (_filter == 'Unread') return !n.isRead;
      if (_filter == 'Stock Alerts' || _filter == 'Alerts') {
        return n.type == NotificationType.stock;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('All', _filter == 'All'),
                    const SizedBox(width: 8),
                    _filterChip('Stock Alerts',
                        _filter == 'Stock Alerts' || _filter == 'Alerts',
                        badge: stockAlertsCount),
                    const SizedBox(width: 8),
                    _filterChip('Unread', _filter == 'Unread',
                        badge: unreadCount),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Notifications List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
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
                            'No notifications found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF777487),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, idx) {
                        final item = filtered[idx];
                        final color = _colorForType(item.type);
                        final itemCardBg = item.isRead
                            ? Colors.white
                            : const Color(0xFFF1F5FD);
                        const itemTitleColor = Color(0xFF17162A);
                        const itemBodyColor = Color(0xFF6B687D);

                        return Material(
                          color: itemCardBg,
                          borderRadius: BorderRadius.circular(16),
                          elevation: item.isRead ? 0.5 : 1,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() => item.isRead = true);
                              if (item.route != null) {
                                widget.onNavigate(item.route!);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Icon badge
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _iconForType(item.type),
                                      color: color,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  // Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                        const SizedBox(height: 6),
                                        Text(
                                          item.body,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: itemBodyColor,
                                            height: 1.4,
                                          ),
                                        ),
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
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
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
