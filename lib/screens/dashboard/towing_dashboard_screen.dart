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

  // Stream مخزن في State لمنع إعادة إنشائه عند setState
  late final Stream<List<Map<String, dynamic>>> _winchOrdersStream;

  // بيانات محفظة الونش المحمّلة بثبات (لا ترجع أبداً إلى 0.00 أثناء التحديث)
  List<DbWalletTransaction> _walletTxs = [];
  late double _accountWalletBalance = widget.profile.walletBalance;
  late double _accountPendingDebt = widget.profile.pendingCommissionDebt;
  bool _walletLoading = true;
  RealtimeChannel? _walletChannel;

  @override
  void initState() {
    super.initState();
    _winchOrdersStream = _db
        .from('mechanic_requests')
        .stream(primaryKey: ['id'])
        .eq('service_type', 'winch')
        .order('created_at', ascending: false)
        .limit(100);

    _notifs.startRealtimeListener(widget.profile.id);
    _syncGps();
    _loadWalletData();
    _subscribeWalletUpdates();
  }

  @override
  void didUpdateWidget(covariant TowingDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _accountWalletBalance = widget.profile.walletBalance;
      _accountPendingDebt = widget.profile.pendingCommissionDebt;
      _loadWalletData();
    }
  }

  Future<void> _loadWalletData({bool silent = false}) async {
    if (!silent && mounted && _walletTxs.isEmpty) {
      setState(() => _walletLoading = true);
    }
    try {
      final results = await Future.wait([
        _db
            .from('customers')
            .select('wallet_balance, pending_commission_debt')
            .eq('id', widget.profile.id)
            .maybeSingle(),
        _db
            .from('wallet_transactions')
            .select()
            .eq('provider_id', widget.profile.id)
            .order('created_at', ascending: false)
            .limit(200),
      ]);

      final customerRow = results[0] as Map<String, dynamic>?;
      final txRows = List<Map<String, dynamic>>.from(results[1] as List);
      final parsedTxs = txRows.map(DbWalletTransaction.fromMap).toList();

      if (!mounted) return;
      setState(() {
        if (customerRow != null) {
          _accountWalletBalance =
              ((customerRow['wallet_balance'] as num?) ?? _accountWalletBalance).toDouble();
          _accountPendingDebt =
              ((customerRow['pending_commission_debt'] as num?) ?? _accountPendingDebt).toDouble();
        }
        _walletTxs = parsedTxs;
        _walletLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _walletLoading = false);
    }
  }

  void _subscribeWalletUpdates() {
    _walletChannel = _db
        .channel('towing_wallet_${widget.profile.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: widget.profile.id,
          ),
          callback: (_) => _loadWalletData(silent: true),
        )
        .subscribe();
  }

  bool _inPeriod(String? createdAt) {
    final dt = DateTime.tryParse(createdAt ?? '')?.toLocal();
    if (dt == null) return true;
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) && !dt.isAfter(range.end.add(const Duration(days: 1)));
  }

  bool _inPeriodDate(DateTime dt) {
    final local = dt.toLocal();
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !local.isBefore(range.start) && !local.isAfter(range.end.add(const Duration(days: 1)));
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
    await _db.from('customers').update({'is_available': val}).eq('id', widget.profile.id);
    widget.onRefreshProfile();
  }

  double? _distanceTo(DbMechanicRequest r) {
    if (_myLat == null || _myLng == null || r.pickupLatitude == null || r.pickupLongitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(_myLat!, _myLng!, r.pickupLatitude!, r.pickupLongitude!) /
        1000.0;
  }

  bool _isVisibleToMe(DbMechanicRequest r) {
    if (r.mechanicId == widget.profile.id) return true;
    if (!_isAvailable || r.status != 'pending') return false;
    if (r.broadcastAll) return true;
    final dist = _distanceTo(r);
    return dist == null || dist <= _maxRadiusKm;
  }

  Future<void> _openGpsNav(double lat, double lng) async {
    await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  void dispose() {
    if (_walletChannel != null) {
      try {
        _db.removeChannel(_walletChannel!);
      } catch (_) {}
      _walletChannel = null;
    }
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
    if (!showPayments) _tab = 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        leading: Navigator.canPop(context) ? const BackButton(color: Colors.white) : null,
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
                animatedRoute(ProviderSubscriptionsScreen(
                  currentPlanCode: widget.profile.subscriptionPlan,
                  onSubscribed: widget.onRefreshProfile,
                )),
              ),
            ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await _notifs.stopRealtimeListener();
              await _db.auth.signOut();
              if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
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
          Expanded(child: _tab == 0 ? _towingOrdersTab(showPayments) : _towingWalletTab()),
        ],
      ),
      bottomNavigationBar: showPayments
          ? BottomNavigationBar(
              currentIndex: _tab,
              selectedItemColor: AppColors.orange,
              onTap: (i) {
                setState(() => _tab = i);
                if (i == 1) _loadWalletData(silent: true);
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'طلبات الونش'),
                BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'المحفظة'),
              ],
            )
          : null,
    );
  }

  Widget _towingOrdersTab(bool showPayments) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _winchOrdersStream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snap.data!
            .where((r) => _inPeriod(r['created_at'] as String?))
            .map(DbMechanicRequest.fromMap)
            .where(_isVisibleToMe)
            .toList();
        final completedCount = orders.where((o) => o.status == 'completed').length;
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
                (label: 'بانتظار القبول', value: pendingCount.toDouble()),
                (label: 'مكتملة', value: completedCount.toDouble()),
              ],
            ),
            const SizedBox(height: 14),
            if (orders.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(_isAvailable ? 'لا توجد طلبات ونش متاحة' : 'أنت في وضع غير متاح'),
                ),
              )
            else
              ...orders.map((o) {
                final d = _distanceTo(o);
                final hasCoords = o.pickupLatitude != null && o.pickupLongitude != null;
                final statusText = StatusLabels.emergency(o.status, progressStep: o.progressStep);
                final isAwaitingCustomerPay = showPayments &&
                    o.mechanicId == widget.profile.id &&
                    o.status == 'completed' &&
                    o.paymentStatus != 'paid';

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
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.navy.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                statusText,
                                style: const TextStyle(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (showPayments && o.paymentStatus == 'paid')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'تم الدفع ✓',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('المشكلة: ${o.description ?? "-"} · الهاتف: ${o.phone ?? "-"}'),
                        Text(
                          'الوجهة: ${o.dropoffAddress ?? "محددة على الخريطة"}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (showPayments && o.totalAmount > 0)
                          Text(
                            'الأجرة: ${o.totalAmount.toStringAsFixed(2)} د.أ',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.orange,
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (hasCoords) ...[
                          SizedBox(
                            height: 140,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: LatLng(o.pickupLatitude!, o.pickupLongitude!),
                                  initialZoom: 14,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.autoparts.app',
                                  ),
                                  MarkerLayer(markers: [
                                    Marker(
                                      point: LatLng(o.pickupLatitude!, o.pickupLongitude!),
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
                                side: const BorderSide(color: AppColors.navy),
                              ),
                              onPressed: () =>
                                  _openGpsNav(o.pickupLatitude!, o.pickupLongitude!),
                              icon: const Icon(Icons.navigation, color: AppColors.navy),
                              label: const Text(
                                'توجيه GPS لموقع العميل',
                                style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (o.status == 'pending')
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _acceptWinch(o),
                              child: const Text('قبول الطلب والانطلاق للعميل'),
                            ),
                          ),
                        if (o.status == 'accepted' && o.mechanicId == widget.profile.id)
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
                                  onPressed: () {
                                    if (o.userId != null) {
                                      _tracker.markEmergencyArrived(
                                        requestId: o.id,
                                        customerUserId: o.userId!,
                                        serviceType: 'winch',
                                      );
                                    }
                                  },
                                  child: const Text('تأكيد الوصول للعميل'),
                                ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _completeWinch(o, showPayments),
                                child: Text(
                                  showPayments
                                      ? 'تأكيد التسليم وإصدار الفاتورة'
                                      : 'تأكيد التسليم وإنهاء الطلب',
                                ),
                              ),
                            ],
                          ),
                        if (isAwaitingCustomerPay) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  o.totalAmount > 0
                                      ? 'بانتظار دفع الزبون (${o.totalAmount.toStringAsFixed(2)} د.أ)'
                                      : 'لم يتم تحديد قيمة الفاتورة بعد',
                                  style: const TextStyle(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => _completeWinch(o, showPayments),
                                child: Text(o.totalAmount > 0 ? 'تعديل المبلغ' : 'إصدار الفاتورة'),
                              ),
                            ],
                          ),
                        ],
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

  Future<void> _acceptWinch(DbMechanicRequest o) async {
    try {
      await _db.from('mechanic_requests').update({
        'status': 'accepted',
        'progress_step': 'on_the_way',
        'mechanic_id': widget.profile.id,
      }).eq('id', o.id).select('id');
      if (o.userId != null) {
        await _notifs.sendNotification(
          targetUserId: o.userId!,
          title: 'ونش الطوارئ في طريقه إليك',
          body: 'تم قبول طلبك، السائق يتحرك الآن نحو موقعك.',
          type: 'order_accepted',
          referenceId: o.id,
        );
        if (o.pickupLatitude != null && o.pickupLongitude != null) {
          await _tracker.startTrackingEmergencyArrival(
            requestId: o.id,
            customerUserId: o.userId!,
            serviceType: 'winch',
            pickupLat: o.pickupLatitude!,
            pickupLng: o.pickupLongitude!,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر قبول الطلب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// إنهاء رحلة الونش: السائق يؤكد/يحدد قيمة الفاتورة النهائية، ثم يدفع الزبون من التطبيق
  Future<void> _completeWinch(DbMechanicRequest o, bool showPayments) async {
    if (!showPayments) {
      try {
        await _db.from('mechanic_requests').update({
          'status': 'completed',
          'progress_step': 'completed',
        }).eq('id', o.id);
        _tracker.stop();
        if (o.userId != null) {
          await _notifs.sendNotification(
            targetUserId: o.userId!,
            title: 'تم إنهاء رحلة الونش بنجاح',
            body: 'شكراً لاستخدامك تطبيق غيارك.',
            type: 'order_completed',
            referenceId: o.id,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إنهاء رحلة الونش بنجاح ✓'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      }
      return;
    }

    final amountCtrl = TextEditingController(
      text: o.totalAmount > 0 ? o.totalAmount.toStringAsFixed(2) : '',
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد التسليم وإصدار الفاتورة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'أكّد قيمة فاتورة السحب النهائية لإرسالها للزبون ليتمكن من الدفع عبر التطبيق:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'قيمة الفاتورة النهائية (د.أ)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              if (amt <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال مبلغ صحيح أكبر من صفر'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              try {
                await _db.from('mechanic_requests').update({
                  'total_amount': amt,
                  'status': 'completed',
                  'progress_step': 'awaiting_payment',
                  'payment_status': 'unpaid',
                }).eq('id', o.id);
                _tracker.stop();

                if (o.userId != null) {
                  await _notifs.sendNotification(
                    targetUserId: o.userId!,
                    title: 'تم تسليم السيارة — فاتورة الونش جاهزة',
                    body: 'قيمة الفاتورة ${amt.toStringAsFixed(2)} د.أ، يمكنك إتمام الدفع الآن.',
                    type: 'invoice_ready',
                    referenceId: o.id,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'تم إصدار الفاتورة بقيمة ${amt.toStringAsFixed(2)} د.أ وإرسالها للزبون ✓',
                      ),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('إرسال الفاتورة للزبون'),
          ),
        ],
      ),
    );
    amountCtrl.dispose();
  }

  Widget _towingWalletTab() {
    final txs = _walletTxs.where((t) => _inPeriodDate(t.createdAt)).toList();
    final periodNet = txs.fold(0.0, (s, t) => s + t.netAmount);
    final periodGross = txs.fold(0.0, (s, t) => s + t.grossAmount);
    final periodComm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
    final allTimeNet = _walletTxs.fold(0.0, (s, t) => s + t.netAmount);
    final effectiveAccountBalance =
        _accountWalletBalance > 0 ? _accountWalletBalance : allTimeNet;

    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: () => _loadWalletData(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: DateRangeFilterBar(
                  period: _period,
                  customRange: _customRange,
                  onChanged: (p, r) => setState(() {
                    _period = p;
                    _customRange = r;
                  }),
                ),
              ),
              IconButton(
                tooltip: 'تحديث المحفظة',
                onPressed: () => _loadWalletData(silent: false),
                icon: const Icon(Icons.refresh, color: AppColors.navy),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'صافي محفظة الونش (بعد العمولة)',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '${effectiveAccountBalance.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'خلال الفترة المختارة — الصافي: ${periodNet.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: AppColors.orange,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'قبل العمولة: ${periodGross.toStringAsFixed(2)} د.أ | العمولة: ${periodComm.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_accountPendingDebt > 0) ...[
                  const Divider(color: Colors.white24, height: 18),
                  Text(
                    'عمولات الدفع النقدي (كاش) المستحقة للمنصة: ${_accountPendingDebt.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_walletLoading && _walletTxs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (txs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'لا توجد حركات مالية ضمن الفترة المختارة',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...txs.map((t) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(
                      'رحلة ونش #${(t.referenceId != null && t.referenceId!.length >= 6) ? t.referenceId!.substring(0, 6) : ""} · ${_paymentMethodArabic(t.paymentMethod)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      'قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} د.أ · العمولة: -${t.commissionAmount.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      '+${t.netAmount.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  String _paymentMethodArabic(String raw) => switch (raw.toLowerCase()) {
        'cash' => 'نقداً (كاش)',
        'apple_pay' => 'Apple Pay',
        'google_pay' => 'Google Pay',
        'visa' || 'card' || 'meps' => 'فيزا / ماستركارد',
        _ => raw,
      };
}