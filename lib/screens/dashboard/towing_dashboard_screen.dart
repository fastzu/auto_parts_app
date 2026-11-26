import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/live_progress_tracker.dart';
import '../../services/location_service.dart';
import '../../services/notifications_service.dart';
import '../../services/wallet_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/status_labels.dart';
import '../../widgets/animations.dart';
import '../mobile/mobile_shell.dart';
import 'provider_subscriptions_screen.dart';

class TowingDashboardScreen extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback onRefreshProfile;
  final VoidCallback onSignedOut;
  final int initialTab;

  const TowingDashboardScreen({
    super.key,
    required this.profile,
    required this.onRefreshProfile,
    required this.onSignedOut,
    this.initialTab = 0,
  });

  @override
  State<TowingDashboardScreen> createState() => _TowingDashboardScreenState();
}

class _TowingDashboardScreenState extends State<TowingDashboardScreen> {
  final _db = Supabase.instance.client;
  final _tracker = LiveProgressTracker.instance;
  final _notifs = NotificationsService.instance;
  final _locationService = LocationService();

  late int _tab = widget.initialTab;
  late bool _isAvailable = widget.profile.isAvailable;
  late double? _myLat = widget.profile.latitude;
  late double? _myLng = widget.profile.longitude;
  final double _maxRadiusKm = 15.0;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;
  String? _trackingRequestId;
  bool _walletUnlocked = false;

  @override
  void initState() {
    super.initState();
    _syncGps();
  }

  bool _inPeriod(String? createdAt) {
    final dt = DateTime.tryParse(createdAt ?? '');
    if (dt == null) return true;
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) &&
        !dt.isAfter(range.end.add(const Duration(days: 1)));
  }

  Future<void> _syncGps() async {
    try {
      final res = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _myLat = res.coordinates.latitude;
        _myLng = res.coordinates.longitude;
      });
      await _db
          .from('customers')
          .update({'latitude': _myLat, 'longitude': _myLng})
          .eq('id', widget.profile.id);
    } catch (_) {}
  }

  Future<void> _toggleAvailability(bool val) async {
    setState(() => _isAvailable = val);
    await _db
        .from('customers')
        .update({'is_available': val})
        .eq('id', widget.profile.id);
    widget.onRefreshProfile();
  }

  Future<void> _onTabTap(int i) async {
    if (i == 1 && !_walletUnlocked) {
      final ok = await WalletAuthService.instance.authenticate(context);
      if (!ok || !mounted) return;
      _walletUnlocked = true;
    }
    setState(() => _tab = i);
  }

  double? _distanceTo(DbMechanicRequest r) {
    if (_myLat == null ||
        _myLng == null ||
        r.pickupLatitude == null ||
        r.pickupLongitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(
          _myLat!,
          _myLng!,
          r.pickupLatitude!,
          r.pickupLongitude!,
        ) /
        1000.0;
  }

  bool _isVisibleToMe(DbMechanicRequest r) {
    if (r.mechanicId == widget.profile.id) return true;
    if (!_isAvailable || r.status != 'pending') return false;
    if (r.broadcastAll) return true;
    final dist = _distanceTo(r);
    return dist == null || dist <= _maxRadiusKm;
  }

  String _winchStatusLabel(String? status, String? progressStep) {
    final st = (status ?? '').trim().toLowerCase();
    final step = (progressStep ?? '').trim().toLowerCase();
    if (st == 'cancelled' || step == 'cancelled') return 'ملغي';
    if (st == 'completed' || step == 'completed') return 'مكتمل وتم الدفع ✓';
    if (st == 'awaiting_payment' || step == 'awaiting_payment') {
      return 'صدرت الفاتورة — بانتظار الدفع';
    }
    if (st == 'quoted' || step == 'quote_sent') {
      return 'بانتظار موافقة العميل على العرض';
    }
    if (step == 'towing') return 'جاري سحب السيارة إلى الوجهة';
    if (step == 'arrived_at_pickup') return 'وصل الونش لموقع العميل ✓';
    if (step == 'on_the_way' || st == 'accepted' || st == 'in_progress') {
      return 'في الطريق لموقع العميل';
    }
    return StatusLabels.emergency(status, progressStep: progressStep);
  }

  double _progressFor(DbMechanicRequest o) {
    final st = o.status.toLowerCase();
    final step = o.progressStep.toLowerCase();
    if (st == 'completed' || step == 'completed') return 1.0;
    if (st == 'awaiting_payment' ||
        step == 'awaiting_payment' ||
        o.paymentStatus == 'invoiced') {
      return 0.88;
    }
    if (step == 'towing') return 0.72;
    if (step == 'arrived_at_pickup') return 0.54;
    if (step == 'on_the_way' || st == 'accepted' || st == 'in_progress') {
      return 0.35;
    }
    if (st == 'quoted' || step == 'quote_sent') return 0.18;
    return 0.0;
  }

  Widget _buildOrderProgressBar(DbMechanicRequest o) {
    final val = _progressFor(o);
    if (val <= 0) return const SizedBox.shrink();
    final pct = (val * 100).round();
    final label = _winchStatusLabel(o.status, o.progressStep);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: AppColors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: val,
              minHeight: 6,
              backgroundColor: Colors.white24,
              color: val >= 1.0 ? AppColors.success : AppColors.orange,
            ),
          ),
        ],
      ),
    );
  }

  void _ensureTrackingActive(DbMechanicRequest o) {
    if (o.mechanicId != widget.profile.id) return;
    final isEnRoute =
        (o.status == 'accepted' || o.status == 'in_progress') &&
        (o.progressStep == 'on_the_way' || o.progressStep.isEmpty);
    if (!isEnRoute) return;
    if (_trackingRequestId == o.id) return;
    if (o.userId == null ||
        o.pickupLatitude == null ||
        o.pickupLongitude == null) {
      return;
    }
    _trackingRequestId = o.id;
    _tracker.startTrackingEmergencyArrival(
      requestId: o.id,
      customerUserId: o.userId!,
      serviceType: 'winch',
      pickupLat: o.pickupLatitude!,
      pickupLng: o.pickupLongitude!,
    );
  }

  Future<void> _openGpsNav(double lat, double lng) async {
    await launchUrl(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  void dispose() {
    _tracker.stop();
    super.dispose();
  }

  void _goHome() {
    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (r) => r.isFirst);
    } else {
      Navigator.pushReplacement(
        context,
        animatedRoute(
          LiveMobileShell(
            profile: widget.profile,
            onRefreshProfile: widget.onRefreshProfile,
            onSignedOut: widget.onSignedOut,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPayments = EnvConfig.paymentsEnabled.value;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        leading: Navigator.canPop(context)
            ? const BackButton(color: Colors.white)
            : null,
        title: Text(
          'ونش الطوارئ · ${widget.profile.fullName ?? ""}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'العودة للرئيسية',
            icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
            onPressed: _goHome,
          ),
          const NotificationBellButton(iconColor: Colors.white),
          if (showPayments)
            IconButton(
              icon: const Icon(Icons.workspace_premium, color: AppColors.orange),
              onPressed: () => Navigator.push(
                context,
                animatedRoute(
                  ProviderSubscriptionsScreen(
                    currentPlanCode: widget.profile.subscriptionPlan,
                    onSubscribed: widget.onRefreshProfile,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await _db.auth.signOut();
              if (context.mounted) {
                Navigator.popUntil(context, (r) => r.isFirst);
              }
              widget.onSignedOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: _isAvailable
                ? AppColors.success.withValues(alpha: 0.12)
                : Colors.red.withValues(alpha: 0.10),
            child: SwitchListTile(
              title: Text(
                _isAvailable ? 'متاح لاستقبال طلبات السحب' : 'غير متاح حالياً',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isAvailable ? AppColors.success : Colors.red,
                  fontSize: 14,
                ),
              ),
              value: _isAvailable,
              activeTrackColor: AppColors.success,
              onChanged: _toggleAvailability,
            ),
          ),
          Expanded(
            child: _tab == 0
                ? _towingOrdersTab()
                : ProviderWalletView(
                    profile: widget.profile,
                    onRefreshProfile: widget.onRefreshProfile,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        selectedItemColor: AppColors.orange,
        onTap: _onTabTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: 'طلبات الونش',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'المحفظة المالية',
          ),
        ],
      ),
    );
  }

  Widget _towingOrdersTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('mechanic_requests')
          .stream(primaryKey: ['id'])
          .eq('service_type', 'winch')
          .order('created_at', ascending: false)
          .limit(100),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data!
            .where((r) => _inPeriod(r['created_at'] as String?))
            .map(DbMechanicRequest.fromMap)
            .where(_isVisibleToMe)
            .toList();
        final completedCount =
            orders.where((o) => o.status == 'completed').length;
        final pendingCount = orders.where((o) => o.status == 'pending').length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DateRangeFilterBar(
              period: _period,
              customRange: _customRange,
              onChanged: (p, r) => setState(() {
                _period = p;
                _customRange = r;
              }),
            ),
            const SizedBox(height: 12),
            InteractiveAnimatedChart(
              title: 'إحصائيات رحلات الونش',
              data: [
                (label: 'كل الطلبات', value: orders.length.toDouble()),
                (label: 'بانتظار عرض سعر', value: pendingCount.toDouble()),
                (label: 'مكتملة', value: completedCount.toDouble()),
              ],
            ),
            const SizedBox(height: 14),
            if (orders.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _isAvailable
                        ? 'لا توجد طلبات ونش متاحة'
                        : 'أنت في وضع غير متاح',
                  ),
                ),
              )
            else
              ...orders.map((o) {
                _ensureTrackingActive(o);
                final d = _distanceTo(o);
                final hasCoords =
                    o.pickupLatitude != null && o.pickupLongitude != null;
                final statusText = _winchStatusLabel(o.status, o.progressStep);
                final statusColor = StatusLabels.colorFor(
                  o.status,
                  progressStep: o.progressStep,
                );
                final isMine = o.mechanicId == widget.profile.id;
                final isQuoted =
                    isMine &&
                    (o.status == 'quoted' || o.progressStep == 'quote_sent');
                final isActiveWork =
                    isMine &&
                    (o.status == 'accepted' || o.status == 'in_progress') &&
                    o.progressStep != 'awaiting_payment';
                final isAwaitingPayment =
                    isMine &&
                    (o.status == 'awaiting_payment' ||
                        o.progressStep == 'awaiting_payment' ||
                        o.paymentStatus == 'invoiced');

                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'طلب سحب · ${o.carDetails}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (d != null)
                              Chip(
                                backgroundColor: AppColors.orangeLight,
                                label: Text(
                                  'يبعد ${d.toStringAsFixed(1)} كم',
                                  style: const TextStyle(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (isMine) _buildOrderProgressBar(o),
                        const SizedBox(height: 4),
                        Text(
                          'المشكلة: ${o.description ?? "-"} · الهاتف: ${o.phone ?? "-"}',
                        ),
                        Text(
                          'الوجهة: ${o.dropoffAddress ?? "محددة على الخريطة"}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (o.totalAmount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'السعر: ${o.totalAmount.toStringAsFixed(2)} د.أ',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.orange,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (hasCoords) ...[
                          SizedBox(
                            height: 145,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: LatLng(
                                    o.pickupLatitude!,
                                    o.pickupLongitude!,
                                  ),
                                  initialZoom: 15.5,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://{s}.google.com/vt/lyrs=m&hl=ar&x={x}&y={y}&z={z}',
                                    subdomains: const [
                                      'mt0',
                                      'mt1',
                                      'mt2',
                                      'mt3',
                                    ],
                                    userAgentPackageName: 'com.ghayarakjo.app',
                                  ),
                                  if (_myLat != null && _myLng != null)
                                    PolylineLayer(
                                      polylines: [
                                        Polyline(
                                          points: [
                                            LatLng(_myLat!, _myLng!),
                                            LatLng(
                                              o.pickupLatitude!,
                                              o.pickupLongitude!,
                                            ),
                                          ],
                                          color: AppColors.orange,
                                          strokeWidth: 4,
                                        ),
                                      ],
                                    ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: LatLng(
                                          o.pickupLatitude!,
                                          o.pickupLongitude!,
                                        ),
                                        width: 44,
                                        height: 44,
                                        child: const Icon(
                                          Icons.location_on,
                                          color: AppColors.orange,
                                          size: 38,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.navy),
                              ),
                              onPressed: () => _openGpsNav(
                                o.pickupLatitude!,
                                o.pickupLongitude!,
                              ),
                              icon: const Icon(
                                Icons.navigation,
                                color: AppColors.navy,
                              ),
                              label: const Text(
                                'توجيه GPS لموقع العميل',
                                style: TextStyle(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (o.status == 'pending')
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _sendQuoteDialog(o),
                              icon: const Icon(Icons.local_offer_outlined),
                              label: const Text('إرسال عرض سعر للعميل'),
                            ),
                          ),
                        if (isQuoted)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _sendQuoteDialog(o),
                                  child: const Text('تعديل العرض'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                  onPressed: () => _withdrawQuote(o),
                                  child: const Text('سحب العرض'),
                                ),
                              ),
                            ],
                          ),
                        if (isActiveWork) ...[
                          if (o.progressStep == 'on_the_way' ||
                              o.progressStep.isEmpty)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.navy,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _markArrived(o),
                                icon: const Icon(Icons.location_on_outlined),
                                label: const Text('تأكيد الوصول لموقع العميل'),
                              ),
                            )
                          else if (o.progressStep == 'arrived_at_pickup')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.orange,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _startTowing(o),
                                icon: const Icon(Icons.local_shipping_outlined),
                                label: const Text('بدء سحب السيارة'),
                              ),
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _finishAndIssueInvoice(o),
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: const Text(
                                  'إنهاء السحب وإصدار الفاتورة النهائية',
                                ),
                              ),
                            ),
                        ],
                        if (isAwaitingPayment)
                          Text(
                            'بانتظار دفع العميل (${o.totalAmount.toStringAsFixed(2)} د.أ)',
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _sendQuoteDialog(DbMechanicRequest o) async {
    final ctrl = TextEditingController(
      text: o.totalAmount > 0 ? o.totalAmount.toStringAsFixed(2) : '',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إرسال عرض سعر للعميل'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'أجرة السحب المقترحة (د.أ)',
            hintText: 'مثال: 25',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final amt = double.tryParse(ctrl.text.trim()) ?? 0.0;
              if (amt <= 0) return;
              try {
                await _db
                    .from('mechanic_requests')
                    .update({
                      'status': 'quoted',
                      'progress_step': 'quote_sent',
                      'mechanic_id': widget.profile.id,
                      'total_amount': amt,
                      'payment_status': 'unpaid',
                    })
                    .eq('id', o.id)
                    .select('id');
                if (o.userId != null) {
                  await _notifs.sendNotification(
                    targetUserId: o.userId!,
                    title: 'وصلك عرض سعر جديد للونش',
                    body: 'عرض سائق الونش أجرة ${amt.toStringAsFixed(2)} د.أ.',
                    type: 'quote_received',
                    referenceId: o.id,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم إرسال عرض السعر ✓'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تعذر إرسال العرض: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('إرسال العرض'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _withdrawQuote(DbMechanicRequest o) async {
    try {
      await _db
          .from('mechanic_requests')
          .update({
            'status': 'pending',
            'progress_step': 'pending',
            'mechanic_id': null,
            'total_amount': 0,
            'payment_status': 'unpaid',
          })
          .eq('id', o.id)
          .select('id');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _markArrived(DbMechanicRequest o) async {
    try {
      await _db
          .from('mechanic_requests')
          .update({
            'status': 'in_progress',
            'progress_step': 'arrived_at_pickup',
          })
          .eq('id', o.id)
          .select('id');
      if (o.userId != null) {
        await _tracker.markEmergencyArrived(
          requestId: o.id,
          customerUserId: o.userId!,
          serviceType: 'winch',
        );
      }
      _trackingRequestId = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر التحديث: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _startTowing(DbMechanicRequest o) async {
    try {
      await _db
          .from('mechanic_requests')
          .update({'status': 'in_progress', 'progress_step': 'towing'})
          .eq('id', o.id)
          .select('id');
      if (o.userId != null) {
        await _notifs.sendNotification(
          targetUserId: o.userId!,
          title: 'بدأت عملية سحب السيارة',
          body: 'الونش يقوم الآن بسحب سيارتك باتجاه الوجهة المحددة.',
          type: 'order_update',
          referenceId: o.id,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر التحديث: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _finishAndIssueInvoice(DbMechanicRequest o) async {
    final ctrl = TextEditingController(
      text: o.totalAmount > 0 ? o.totalAmount.toStringAsFixed(2) : '',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء السحب وإصدار الفاتورة النهائية'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'قيمة الفاتورة النهائية (د.أ)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final finalAmt = double.tryParse(ctrl.text.trim()) ?? 0.0;
              if (finalAmt <= 0) return;
              try {
                await _db
                    .from('mechanic_requests')
                    .update({
                      'status': 'awaiting_payment',
                      'progress_step': 'awaiting_payment',
                      'total_amount': finalAmt,
                      'payment_status': 'invoiced',
                    })
                    .eq('id', o.id)
                    .select('id');
                _tracker.stop();
                _trackingRequestId = null;

                if (o.userId != null) {
                  await _notifs.sendNotification(
                    targetUserId: o.userId!,
                    title: 'صدرت الفاتورة النهائية',
                    body: 'قيمة الفاتورة ${finalAmt.toStringAsFixed(2)} د.أ.',
                    type: 'invoice_issued',
                    referenceId: o.id,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم إصدار الفاتورة ✓'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('خطأ: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('إصدار الفاتورة'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
}