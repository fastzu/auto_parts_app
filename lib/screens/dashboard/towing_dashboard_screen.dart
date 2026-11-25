import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../services/app_locale_service.dart';
import '../../services/live_progress_tracker.dart';
import '../../services/location_service.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
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
  final _loc = AppLocaleService.instance;

  late int _tab = widget.initialTab;
  late bool _isAvailable = widget.profile.isAvailable;
  late double? _myLat = widget.profile.latitude;
  late double? _myLng = widget.profile.longitude;
  final double _maxRadiusKm = 15.0;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;
  final Set<String> _trackingWinchIds = {};

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
      await _db.from('customers').update({
        'latitude': _myLat,
        'longitude': _myLng,
      }).eq('id', widget.profile.id);
    } catch (_) {}
  }

  Future<void> _toggleAvailability(bool val) async {
    setState(() => _isAvailable = val);
    await _db
        .from('customers')
        .update({'is_available': val}).eq('id', widget.profile.id);
    widget.onRefreshProfile();
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
    if (r.rejectedProviderIds.contains(widget.profile.id)) return false;
    if (!_isAvailable || r.status != 'pending') return false;
    if (r.broadcastAll) return true;
    final dist = _distanceTo(r);
    return dist == null || dist <= _maxRadiusKm;
  }

  void _ensureLiveBroadcast(DbMechanicRequest o) {
    if (o.mechanicId != widget.profile.id ||
        o.status != 'accepted' ||
        o.progressStep != 'on_the_way' ||
        o.userId == null ||
        o.pickupLatitude == null ||
        o.pickupLongitude == null) {
      return;
    }
    if (_trackingWinchIds.contains(o.id)) return;
    _trackingWinchIds.add(o.id);
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
        animatedRoute(LiveMobileShell(
          profile: widget.profile,
          onRefreshProfile: widget.onRefreshProfile,
          onSignedOut: widget.onSignedOut,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showSubs = EnvConfig.subscriptionsEnabled.value;
    if (!showPayments) _tab = 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        leading:
            Navigator.canPop(context) ? const BackButton(color: Colors.white) : null,
        title: Text(
          '${_loc.tr("ونش الطوارئ", "Towing Winch")} · ${widget.profile.fullName ?? ""}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: _loc.tr('العودة للرئيسية', 'Home'),
            icon: const Icon(Icons.storefront, color: Colors.white),
            onPressed: _goHome,
          ),
          const NotificationBellButton(iconColor: Colors.white),
          if (showSubs)
            IconButton(
              icon: const Icon(Icons.workspace_premium,
                  color: AppColors.orange),
              onPressed: () => Navigator.push(
                context,
                animatedRoute(ProviderSubscriptionsScreen(
                  currentPlanCode: widget.profile.subscriptionPlan,
                  onSubscribed: widget.onRefreshProfile,
                )),
              ),
            ),
          IconButton(
            tooltip: _loc.tr('تسجيل الخروج', 'Sign Out'),
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
                _isAvailable
                    ? _loc.tr(
                        'حالتي: متاح لاستقبال الطلبات', 'Status: Online')
                    : _loc.tr(
                        'حالتي: غير متاح حالياً', 'Status: Offline'),
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
            child: _tab == 0 ? _towingOrdersTab(showPayments) : _towingWalletTab(),
          ),
        ],
      ),
      bottomNavigationBar: showPayments
          ? BottomNavigationBar(
              currentIndex: _tab,
              selectedItemColor: AppColors.orange,
              onTap: (i) => setState(() => _tab = i),
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.local_shipping),
                  label: _loc.tr('طلبات الونش', 'Winch Orders'),
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.account_balance_wallet),
                  label: _loc.tr('المحفظة', 'Wallet'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _towingOrdersTab(bool showPayments) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('mechanic_requests')
          .stream(primaryKey: ['id'])
          .eq('service_type', 'winch')
          .order('created_at', ascending: false),
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
              title: _loc.tr('إحصائيات رحلات الونش', 'Towing Trips Analytics'),
              data: [
                (
                  label: _loc.tr('كل الطلبات', 'Total'),
                  value: orders.length.toDouble()
                ),
                (
                  label: _loc.tr('بانتظار عرض سعر', 'Pending'),
                  value: pendingCount.toDouble()
                ),
                (
                  label: _loc.tr('مكتملة', 'Completed'),
                  value: completedCount.toDouble()
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (orders.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(_isAvailable
                      ? _loc.tr('لا توجد طلبات ونش متاحة', 'No towing requests')
                      : _loc.tr('أنت في وضع غير متاح', 'You are offline')),
                ),
              )
            else
              ...orders.map((o) {
                _ensureLiveBroadcast(o);
                final d = _distanceTo(o);
                final hasCoords =
                    o.pickupLatitude != null && o.pickupLongitude != null;
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
                                '${_loc.tr("طلب سحب", "Tow Order")} · ${o.carDetails}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            if (d != null)
                              Chip(
                                backgroundColor: AppColors.orangeLight,
                                label: Text(
                                  _loc.tr('يبعد ${d.toStringAsFixed(1)} كم',
                                      '${d.toStringAsFixed(1)} km'),
                                  style: const TextStyle(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          '${_loc.tr("المشكلة", "Issue")}: ${o.description ?? "-"} · ${_loc.tr("الهاتف", "Phone")}: ${o.phone ?? "-"}',
                        ),
                        Text(
                          '${_loc.tr("الوجهة", "Dropoff")}: ${o.dropoffAddress ?? _loc.tr("محددة على الخريطة", "Map pin")}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (o.quotedPrice > 0 || o.totalAmount > 0)
                          Text(
                            '${_loc.tr("عرض السعر / الفاتورة", "Quote / Invoice")}: ${(o.totalAmount > 0 ? o.totalAmount : o.quotedPrice).toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.orange,
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (hasCoords) ...[
                          SizedBox(
                            height: 145,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: LatLng(
                                      o.pickupLatitude!, o.pickupLongitude!),
                                  initialZoom: 14,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                                    subdomains: const ['a', 'b', 'c', 'd'],
                                    userAgentPackageName:
                                        'com.autoparts.ghiyarak',
                                    retinaMode: true,
                                  ),
                                  MarkerLayer(markers: [
                                    Marker(
                                      point: LatLng(o.pickupLatitude!,
                                          o.pickupLongitude!),
                                      width: 44,
                                      height: 44,
                                      child: const Icon(
                                        Icons.location_on,
                                        color: AppColors.orange,
                                        size: 38,
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  side:
                                      const BorderSide(color: AppColors.navy)),
                              onPressed: () => _openGpsNav(
                                  o.pickupLatitude!, o.pickupLongitude!),
                              icon: const Icon(Icons.navigation,
                                  color: AppColors.navy),
                              label: Text(
                                _loc.tr('توجيه GPS لموقع العميل',
                                    'Navigate to Pickup'),
                                style: const TextStyle(
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => _sendWinchQuoteDialog(o),
                              icon: const Icon(Icons.request_quote_rounded),
                              label: Text(_loc.tr(
                                'قبول وإرسال عرض سعر للزبون',
                                'Accept & Send Price Quote',
                              )),
                            ),
                          ),
                        if (o.status == 'quote_sent' &&
                            o.mechanicId == widget.profile.id)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.orangeLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _loc.tr(
                                'تم إرسال عرض السعر (${o.quotedPrice.toStringAsFixed(2)} د.أ) — بانتظار موافقة الزبون...',
                                'Quote sent (${o.quotedPrice.toStringAsFixed(2)} JOD) — awaiting customer...',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                        if (o.status == 'accepted' &&
                            o.mechanicId == widget.profile.id)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (o.progressStep == 'on_the_way')
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.navy,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () async {
                                    if (o.userId != null) {
                                      await _tracker.markEmergencyArrived(
                                        requestId: o.id,
                                        customerUserId: o.userId!,
                                        serviceType: 'winch',
                                      );
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppColors.success,
                                            content: Text(_loc.tr(
                                              'تم تأكيد وصولك وإشعار الزبون ✓',
                                              'Arrival confirmed & customer notified ✓',
                                            )),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: Text(_loc.tr(
                                      'تأكيد الوصول للعميل', 'Confirm Arrival')),
                                ),
                              if (o.progressStep != 'awaiting_payment')
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () =>
                                      _issueWinchInvoice(o, showPayments),
                                  icon:
                                      const Icon(Icons.receipt_long, size: 17),
                                  label: Text(
                                    showPayments
                                        ? _loc.tr('إصدار وتسليم الفاتورة',
                                            'Issue Final Invoice')
                                        : _loc.tr('تأكيد التسليم والإنهاء',
                                            'Complete Dropoff'),
                                  ),
                                )
                              else
                                Chip(
                                  backgroundColor:
                                      AppColors.success.withValues(alpha: 0.14),
                                  label: Text(
                                    _loc.tr(
                                      'تم إصدار الفاتورة ✓ بانتظار دفع الزبون',
                                      'Invoice Issued ✓ Awaiting Payment',
                                    ),
                                    style: const TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
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

  Future<void> _sendWinchQuoteDialog(DbMechanicRequest o) async {
    final priceCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool sending = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(_loc.tr('إرسال عرض سعر للسحب', 'Send Towing Quote')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceCtrl,
                enabled: !sending,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText:
                      _loc.tr('الأجرة المقترحة (د.أ)', 'Quoted Price (JOD)'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                enabled: !sending,
                decoration: InputDecoration(
                  labelText: _loc.tr(
                      'ملاحظات / وقت الوصول (اختياري)', 'Notes / ETA'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: Text(_loc.tr('إلغاء', 'Cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: sending
                  ? null
                  : () async {
                      final price =
                          double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                      if (price <= 0) return;
                      setS(() => sending = true);
                      try {
                        await _db.from('mechanic_requests').update({
                          'status': 'quote_sent',
                          'progress_step': 'pending',
                          'mechanic_id': widget.profile.id,
                          'quoted_price': price,
                          'total_amount': price,
                          'quote_notes': notesCtrl.text.trim(),
                        }).eq('id', o.id);

                        if (o.userId != null) {
                          await _notifs.sendNotification(
                            targetUserId: o.userId!,
                            title: 'وصلك عرض سعر من ونش الطوارئ 🚚',
                            body:
                                'قدّم ${widget.profile.fullName ?? "سائق الونش"} عرض سعر بقيمة ${price.toStringAsFixed(2)} د.أ — افتح التطبيق للقبول أو الرفض.',
                            type: 'quote_sent',
                            referenceId: o.id,
                          );
                        }
                        await _notifs.sendNotification(
                          targetUserId: widget.profile.id,
                          title: 'تم إرسال عرض السعر بنجاح ✓',
                          body:
                              'تم إرسال عرض بقيمة ${price.toStringAsFixed(2)} د.أ للزبون وبانتظار موافقته.',
                          type: 'quote_sent_confirm',
                          referenceId: o.id,
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.success,
                              content: Text(_loc.tr(
                                'تم إرسال عرض السعر للزبون بنجاح ✓',
                                'Quote sent successfully ✓',
                              )),
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setS(() => sending = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                backgroundColor: Colors.red,
                                content: Text('$e')),
                          );
                        }
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(_loc.tr('إرسال العرض', 'Send Quote')),
            ),
          ],
        ),
      ),
    );
    priceCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _issueWinchInvoice(
    DbMechanicRequest o,
    bool showPayments,
  ) async {
    if (!showPayments) {
      await _db.from('mechanic_requests').update({
        'status': 'completed',
        'progress_step': 'completed',
      }).eq('id', o.id);
      if (o.userId != null) {
        await _notifs.sendNotification(
          targetUserId: o.userId!,
          title: 'تم تسليم السيارة بنجاح ✓',
          body: 'انتهت رحلة الونش بنجاح! يمكنك الآن تقييم السائق.',
          type: 'order_completed',
          referenceId: o.id,
        );
      }
      return;
    }

    final initialAmt = o.totalAmount > 0 ? o.totalAmount : o.quotedPrice;
    final amountCtrl = TextEditingController(
      text: initialAmt > 0 ? initialAmt.toStringAsFixed(2) : '',
    );
    bool submitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(_loc.tr(
            'إصدار فاتورة الونش وإرسالها للزبون',
            'Issue Towing Invoice',
          )),
          content: TextField(
            controller: amountCtrl,
            enabled: !submitting,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  _loc.tr('المبلغ النهائي (د.أ)', 'Final Amount (JOD)'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: Text(_loc.tr('إلغاء', 'Cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final amt =
                          double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                      if (amt <= 0) return;
                      setS(() => submitting = true);
                      try {
                        await _db.from('mechanic_requests').update({
                          'total_amount': amt,
                          'progress_step': 'awaiting_payment',
                          'invoice_issued_at':
                              DateTime.now().toIso8601String(),
                        }).eq('id', o.id);

                        if (o.userId != null) {
                          await _notifs.sendNotification(
                            targetUserId: o.userId!,
                            title: 'تم إصدار فاتورة الونش — يرجى الدفع 🧾',
                            body:
                                'وصلت سيارتك بسلامة! قيمة الفاتورة ${amt.toStringAsFixed(2)} د.أ — يرجى إتمام الدفع الآن.',
                            type: 'invoice_issued',
                            referenceId: o.id,
                          );
                        }
                        await _notifs.sendNotification(
                          targetUserId: widget.profile.id,
                          title: 'تم إصدار الفاتورة بنجاح ✓',
                          body:
                              'تم إرسال فاتورة بقيمة ${amt.toStringAsFixed(2)} د.أ للزبون للدفع.',
                          type: 'invoice_issued_confirm',
                          referenceId: o.id,
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.success,
                              content: Text(_loc.tr(
                                'تم إصدار الفاتورة بنجاح وإشعار الزبون للدفع ✓',
                                'Invoice issued & customer notified ✓',
                              )),
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setS(() => submitting = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                backgroundColor: Colors.red,
                                content: Text('$e')),
                          );
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(_loc.tr('إرسال الفاتورة', 'Send Invoice')),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
  }

  Widget _towingWalletTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('wallet_transactions')
          .stream(primaryKey: ['id'])
          .eq('provider_id', widget.profile.id)
          .order('created_at', ascending: false),
      builder: (context, snap) {
        final txs = (snap.data ?? [])
            .where((t) => _inPeriod(t['created_at'] as String?))
            .map(DbWalletTransaction.fromMap)
            .toList();
        final net = txs.fold(0.0, (s, t) => s + t.netAmount);
        final gross = txs.fold(0.0, (s, t) => s + t.grossAmount);
        final comm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
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
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_loc.tr('صافي محفظة الونش', 'Net Towing Wallet'),
                      style: const TextStyle(color: Colors.white70)),
                  Text(
                    '${net.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_loc.tr("قبل العمولة", "Gross")}: ${gross.toStringAsFixed(2)} | ${_loc.tr("العمولة", "Fee")}: ${comm.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...txs.map((t) => Card(
                  child: ListTile(
                    title: Text(
                        '${_loc.tr("رحلة ونش", "Trip")} #${t.referenceId?.substring(0, 6) ?? ""}'),
                    subtitle: Text(
                      '${_loc.tr("قبل العمولة", "Gross")}: ${t.grossAmount} · ${_loc.tr("العمولة", "Fee")}: -${t.commissionAmount.toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      '+${t.netAmount.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}