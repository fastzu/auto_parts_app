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
import '../mobile/add_product_screen.dart';
import '../mobile/mobile_shell.dart';
import 'merchant_products_dashboard.dart';
import 'provider_subscriptions_screen.dart';

class WorkshopEmergencyDashboard extends StatefulWidget {
  final CustomerProfile profile;
  final VoidCallback onRefreshProfile;
  final VoidCallback onSignedOut;
  final int initialTab;

  const WorkshopEmergencyDashboard({
    super.key,
    required this.profile,
    required this.onRefreshProfile,
    required this.onSignedOut,
    this.initialTab = 0,
  });

  @override
  State<WorkshopEmergencyDashboard> createState() => _WorkshopEmergencyDashboardState();
}

class _WorkshopEmergencyDashboardState extends State<WorkshopEmergencyDashboard> {
  final _db = Supabase.instance.client;
  final _notifs = NotificationsService.instance;
  final _tracker = LiveProgressTracker.instance;
  final _locationService = LocationService();

  late int _tab = widget.initialTab;
  late bool _isAvailable = widget.profile.isAvailable;
  late double? _myLat = widget.profile.latitude ?? widget.profile.workshopLatitude;
  late double? _myLng = widget.profile.longitude ?? widget.profile.workshopLongitude;
  final double _maxRadiusKm = 15.0;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;

  // Streams مخزنة في State لمنع إعادة إنشائها أو تصفيرها عند setState
  late final Stream<List<Map<String, dynamic>>> _emergencyStream;
  late final Stream<List<Map<String, dynamic>>> _appointmentsStream;

  // بيانات المحفظة المحملة بشكل مستقر (لا ترجع أبداً إلى 0.00 أثناء التحديث)
  List<DbWalletTransaction> _walletTxs = [];
  late double _accountWalletBalance = widget.profile.walletBalance;
  late double _accountPendingDebt = widget.profile.pendingCommissionDebt;
  bool _walletLoading = true;
  RealtimeChannel? _walletChannel;

  List<({int id, String label})> get _menuItems {
    final list = <({int id, String label})>[
      (id: 0, label: 'نظرة عامة'),
      (id: 1, label: 'طلبات الطوارئ'),
      (id: 2, label: 'حجوزات الورشة'),
      (id: 3, label: 'قطع الغيار والمخزون'),
    ];
    if (EnvConfig.paymentsEnabled.value) {
      list.add((id: 4, label: 'المحفظة المالية'));
      list.add((id: 5, label: 'الاشتراك والباقة'));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _emergencyStream = _db
        .from('mechanic_requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100);
    _appointmentsStream = _db
        .from('workshop_appointments')
        .stream(primaryKey: ['id'])
        .eq('workshop_id', widget.profile.id)
        .order('created_at', ascending: false)
        .limit(100);

    _notifs.startRealtimeListener(widget.profile.id);
    _syncProviderGps();
    _loadWalletData();
    _subscribeWalletUpdates();
  }

  @override
  void didUpdateWidget(covariant WorkshopEmergencyDashboard oldWidget) {
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
        .channel('workshop_wallet_${widget.profile.id}')
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

  Future<void> _syncProviderGps() async {
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

  double? _distanceToRequest(DbMechanicRequest r) {
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
    final dist = _distanceToRequest(r);
    return dist == null || dist <= _maxRadiusKm;
  }

  Future<void> _openGpsNavigation(double lat, double lng) async {
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

  void _goHome({bool closeDrawerFirst = false}) {
    if (closeDrawerFirst && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
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
    final isWide = MediaQuery.of(context).size.width >= 850;
    final showPayments = EnvConfig.paymentsEnabled.value;
    if (!showPayments && (_tab == 4 || _tab == 5)) {
      _tab = 0;
    }

    return Scaffold(
      appBar: isWide
          ? null
          : AppBar(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              actionsIconTheme: const IconThemeData(color: Colors.white),
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              title: Text(
                widget.profile.fullName ?? 'لوحة الورشة',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              actions: [
                IconButton(
                  tooltip: 'العودة للرئيسية',
                  icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
                  onPressed: _goHome,
                ),
                const NotificationBellButton(iconColor: Colors.white),
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
      drawer: isWide ? null : Drawer(child: _buildSidebar(isDrawer: true)),
      body: Row(
        children: [
          if (isWide) SizedBox(width: 240, child: _buildSidebar(isDrawer: false)),
          Expanded(
            child: Column(
              children: [
                Container(
                  color: _isAvailable
                      ? AppColors.success.withValues(alpha: 0.10)
                      : Colors.red.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _isAvailable
                                ? 'متاح لاستقبال الطلبات والمواعيد'
                                : 'غير متاح حالياً',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _isAvailable ? AppColors.success : Colors.red,
                            ),
                          ),
                          value: _isAvailable,
                          activeTrackColor: AppColors.success,
                          onChanged: _toggleAvailability,
                        ),
                      ),
                      if (isWide) const NotificationBellButton(iconColor: AppColors.navy),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: KeyedSubtree(
                      key: ValueKey(_tab),
                      child: switch (_tab) {
                        1 => _buildEmergencyTab(),
                        2 => _buildAppointmentsTab(),
                        3 => const MerchantProductsDashboard(embedded: true),
                        4 => _buildWalletTab(),
                        5 => ProviderSubscriptionsScreen(
                            currentPlanCode: widget.profile.subscriptionPlan,
                            onSubscribed: widget.onRefreshProfile,
                          ),
                        _ => _buildOverviewTab(isWide),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar({required bool isDrawer}) {
    final items = _menuItems;
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.profile.fullName ?? 'اسم النشاط',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                onPressed: () async {
                  await _notifs.stopRealtimeListener();
                  await _db.auth.signOut();
                  if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
                  widget.onSignedOut();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.grid_view_rounded, color: Colors.white),
            title: const Text(
              'العودة للرئيسية (الاختصارات)',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            onTap: () => _goHome(closeDrawerFirst: isDrawer),
          ),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          ...items.map((item) {
            final active = _tab == item.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _tab = item.id);
                  if (item.id == 4) _loadWalletData(silent: true);
                  if (isDrawer) Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: active ? AppColors.orange : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white70,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(bool isWide) {
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _emergencyStream,
      builder: (context, reqSnap) {
        final rawReqs =
            (reqSnap.data ?? []).where((r) => _inPeriod(r['created_at'] as String?)).toList();
        final reqs = rawReqs
            .map(DbMechanicRequest.fromMap)
            .where((r) => (showWinch || r.serviceType != 'winch') && _isVisibleToMe(r))
            .toList();
        final activeEmergencies = reqs.where((r) => r.status != 'completed').length;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _appointmentsStream,
          builder: (context, apptSnap) {
            final appts =
                (apptSnap.data ?? []).where((a) => _inPeriod(a['created_at'] as String?)).toList();
            final completedAppts = appts.where((a) => a['status'] == 'completed').length;
            final pendingAppts = appts.where((a) => a['status'] == 'pending').length;

            final chartData = [
              (label: 'طوارئ نشطة', value: activeEmergencies.toDouble()),
              (label: 'كل المواعيد', value: appts.length.toDouble()),
              (label: 'قيد الانتظار', value: pendingAppts.toDouble()),
              (label: 'مكتملة', value: completedAppts.toDouble()),
            ];

            final txTotalNet = _walletTxs.fold(0.0, (s, t) => s + t.netAmount);
            final liveWallet =
                _accountWalletBalance > 0 ? _accountWalletBalance : txTotalNet;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'نظرة عامة',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () =>
                            Navigator.push(context, animatedRoute(const AddProductScreen())),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('إضافة قطعة'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DateRangeFilterBar(
                    period: _period,
                    customRange: _customRange,
                    onChanged: (p, r) => setState(() {
                      _period = p;
                      _customRange = r;
                    }),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: isWide ? (showPayments ? 4 : 3) : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: isWide ? 1.75 : 1.3,
                    children: [
                      _kpiCard('طلبات طوارئ نشطة', activeEmergencies, Icons.car_crash),
                      _kpiCard('حجوزات الورشة', appts.length, Icons.event_available),
                      _kpiCard('سعة الورشة القصوى', widget.profile.maxCarCapacity, Icons.garage),
                      if (showPayments)
                        _kpiCard(
                          'رصيد المحفظة (د.أ)',
                          liveWallet.round(),
                          Icons.account_balance_wallet,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InteractiveAnimatedChart(
                    title: 'إحصائيات الورشة والطوارئ التفاعلية',
                    data: chartData,
                  ),
                  const SizedBox(height: 16),
                  _bottomCard(
                    'أحدث مواعيد الورشة',
                    appts.isEmpty
                        ? [const Text('لا توجد مواعيد ضمن هذه الفترة')]
                        : appts
                            .take(4)
                            .map((a) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${a['appointment_time']} · ${a['appointment_date']}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      Flexible(
                                        child: Text(
                                          StatusLabels.appointment(
                                            a['status'] as String?,
                                            progressStep: a['progress_step'] as String?,
                                          ),
                                          style: const TextStyle(
                                            color: AppColors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _kpiCard(String title, int val, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PulseBlink(child: Icon(icon, color: AppColors.orange, size: 22)),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          AnimatedCounter(
            value: val,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _bottomCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildEmergencyTab() {
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _emergencyStream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final reqs = snap.data!
            .where((r) => _inPeriod(r['created_at'] as String?))
            .map(DbMechanicRequest.fromMap)
            .where((r) =>
                (r.serviceType != 'winch' || (showWinch && widget.profile.hasTowing)) &&
                _isVisibleToMe(r))
            .toList();

        if (reqs.isEmpty) {
          return Center(
            child: Text(_isAvailable ? 'لا توجد طلبات طوارئ متاحة حالياً' : 'أنت في وضع غير متاح'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reqs.length,
          itemBuilder: (_, i) {
            final r = reqs[i];
            final distKm = _distanceToRequest(r);
            final hasCoords = r.pickupLatitude != null && r.pickupLongitude != null;
            final statusText = StatusLabels.emergency(r.status, progressStep: r.progressStep);
            final isAwaitingCustomerPay = showPayments &&
                r.mechanicId == widget.profile.id &&
                r.status == 'completed' &&
                r.paymentStatus != 'paid';

            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${r.serviceType == 'winch' ? 'طلب ونش' : 'ميكانيكي طوارئ'} · ${r.carDetails}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        if (distKm != null)
                          Chip(
                            backgroundColor: AppColors.orangeLight,
                            label: Text(
                              'يبعد ${distKm.toStringAsFixed(1)} كم',
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
                        if (showPayments && r.paymentStatus == 'paid')
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
                    Text('المشكلة: ${r.description ?? "-"} · الهاتف: ${r.phone ?? "-"}'),
                    Text('العنوان: ${r.dropoffAddress ?? "موقع العميل"}'),
                    if (showPayments && r.totalAmount > 0)
                      Text(
                        'قيمة الفاتورة: ${r.totalAmount.toStringAsFixed(2)} د.أ',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.orange),
                      ),
                    const SizedBox(height: 10),
                    if (hasCoords) ...[
                      SizedBox(
                        height: 140,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(r.pickupLatitude!, r.pickupLongitude!),
                              initialZoom: 14,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.autoparts.app',
                              ),
                              MarkerLayer(markers: [
                                Marker(
                                  point: LatLng(r.pickupLatitude!, r.pickupLongitude!),
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
                              _openGpsNavigation(r.pickupLatitude!, r.pickupLongitude!),
                          icon: const Icon(Icons.navigation, color: AppColors.navy),
                          label: const Text(
                            'توجيه GPS لموقع العميل',
                            style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (r.status == 'pending')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _acceptEmergency(r),
                          child: const Text('قبول الطلب والانطلاق'),
                        ),
                      ),
                    if (r.status == 'accepted' && r.mechanicId == widget.profile.id)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (r.progressStep == 'on_the_way')
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.navy,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                if (r.userId != null) {
                                  _tracker.markEmergencyArrived(
                                    requestId: r.id,
                                    customerUserId: r.userId!,
                                    serviceType: r.serviceType,
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
                            onPressed: () => _finishEmergencyAndBill(r),
                            child: Text(
                              showPayments ? 'إنهاء الطلب وإصدار الفاتورة' : 'إنهاء الطلب',
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
                              r.totalAmount > 0
                                  ? 'بانتظار دفع الزبون (${r.totalAmount.toStringAsFixed(2)} د.أ)'
                                  : 'لم يتم إدخال قيمة الفاتورة بعد',
                              style: const TextStyle(
                                color: AppColors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => _finishEmergencyAndBill(r),
                            child: Text(r.totalAmount > 0 ? 'تعديل المبلغ' : 'إصدار الفاتورة'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// إنهاء طلب الطوارئ: الميكانيكي فقط يدخل/يؤكد المبلغ النهائي ليظهر للزبون للدفع
  Future<void> _finishEmergencyAndBill(DbMechanicRequest r) async {
    if (!EnvConfig.paymentsEnabled.value) {
      await _db
          .from('mechanic_requests')
          .update({'status': 'completed', 'progress_step': 'completed'})
          .eq('id', r.id);
      _tracker.stop();
      if (r.userId != null) {
        await _notifs.sendNotification(
          targetUserId: r.userId!,
          title: 'تم إنهاء طلب الطوارئ',
          body: 'شكراً لاستخدامك تطبيق غيارك.',
          type: 'order_completed',
          referenceId: r.id,
        );
      }
      return;
    }

    final amountCtrl = TextEditingController(
      text: r.totalAmount > 0 ? r.totalAmount.toStringAsFixed(2) : '',
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء طلب الطوارئ وإصدار الفاتورة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'أدخل قيمة الفاتورة النهائية المتفق عليها ليتم إرسالها للزبون وإتمام الدفع:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'قيمة الفاتورة (د.أ)',
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
                }).eq('id', r.id);
                _tracker.stop();
                if (r.userId != null) {
                  await _notifs.sendNotification(
                    targetUserId: r.userId!,
                    title: 'تم إنهاء الخدمة — الفاتورة جاهزة للدفع',
                    body: 'قيمة فاتورة طلب الطوارئ ${amt.toStringAsFixed(2)} د.أ.',
                    type: 'invoice_ready',
                    referenceId: r.id,
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
                    SnackBar(content: Text('تعذر إصدار الفاتورة: $e'), backgroundColor: Colors.red),
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

  Future<void> _acceptEmergency(DbMechanicRequest r) async {
    try {
      await _db.from('mechanic_requests').update({
        'status': 'accepted',
        'progress_step': 'on_the_way',
        'mechanic_id': widget.profile.id,
      }).eq('id', r.id).select('id');

      if (r.userId != null) {
        await _notifs.sendNotification(
          targetUserId: r.userId!,
          title: 'تم قبول طلب الطوارئ',
          body: 'المزود في طريقه إليك الآن.',
          type: 'order_accepted',
          referenceId: r.id,
        );
        if (r.pickupLatitude != null && r.pickupLongitude != null) {
          await _tracker.startTrackingEmergencyArrival(
            requestId: r.id,
            customerUserId: r.userId!,
            serviceType: r.serviceType,
            pickupLat: r.pickupLatitude!,
            pickupLng: r.pickupLongitude!,
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

  Widget _buildAppointmentsTab() {
    final showPayments = EnvConfig.paymentsEnabled.value;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _appointmentsStream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('لا توجد مواعيد محجوزة حالياً'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final a = list[i];
            final date = a['appointment_date'] as String;
            final acceptedOnDate =
                list.where((x) => x['appointment_date'] == date && x['status'] == 'accepted').length;
            final isFull = acceptedOnDate >= widget.profile.maxCarCapacity;
            final statusText = StatusLabels.appointment(
              a['status'] as String?,
              progressStep: a['progress_step'] as String?,
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${a['appointment_date']} · ${a['appointment_time']}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            statusText,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text((a['service_description'] as String?) ?? ''),
                    if (showPayments && ((a['total_amount'] as num?)?.toDouble() ?? 0) > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'قيمة الفاتورة: ${((a['total_amount'] as num).toDouble()).toStringAsFixed(2)} د.أ',
                        style: const TextStyle(
                          color: AppColors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (a['status'] == 'pending')
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (!isFull)
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _acceptAppointment(a),
                              child: const Text('قبول الموعد'),
                            )
                          else
                            const Text(
                              'الورشة ممتلئة لهذا اليوم!',
                              style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold),
                            ),
                          OutlinedButton(
                            onPressed: () => _proposeReschedule(a),
                            child: const Text('اقتراح موعد آخر'),
                          ),
                        ],
                      ),
                    if (a['status'] == 'accepted') ...[
                      const Divider(),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _stepBtn(a, 'diagnosis', 'فحص السيارة'),
                          _stepBtn(a, 'repairing', 'قيد الإصلاح'),
                          _stepBtn(a, 'testing', 'فحص نهائي'),
                          ActionChip(
                            backgroundColor: AppColors.orange,
                            label: Text(
                              showPayments ? 'جاهزة للتسليم + فاتورة' : 'جاهزة للتسليم',
                              style: const TextStyle(color: Colors.white),
                            ),
                            onPressed: () => _finishAndBill(a),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _stepBtn(Map<String, dynamic> appt, String stepKey, String label) {
    final active = appt['progress_step'] == stepKey;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      selectedColor: AppColors.navy,
      labelStyle: TextStyle(color: active ? Colors.white : AppColors.textPrimary),
      onSelected: (_) async {
        try {
          await _db
              .from('workshop_appointments')
              .update({'progress_step': stepKey})
              .eq('id', appt['id'])
              .select('id');
          if (appt['user_id'] != null) {
            await _notifs.sendNotification(
              targetUserId: appt['user_id'] as String,
              title: 'تحديث حالة سيارتك في الورشة',
              body: 'أصبحت سيارتك الآن في مرحلة: $label',
              type: 'appointment_update',
              referenceId: appt['id'] as String,
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تعذر التحديث: $e'), backgroundColor: Colors.red),
            );
          }
        }
      },
    );
  }

  Future<void> _acceptAppointment(Map<String, dynamic> a) async {
    await _db
        .from('workshop_appointments')
        .update({'status': 'accepted', 'progress_step': 'on_the_way'})
        .eq('id', a['id'])
        .select('id');
    await _notifs.sendNotification(
      targetUserId: a['user_id'] as String,
      title: 'تم قبول موعد الورشة',
      body: 'موعدك مؤكد بتاريخ ${a['appointment_date']} الساعة ${a['appointment_time']}.',
      type: 'order_accepted',
      referenceId: a['id'] as String,
    );
  }

  Future<void> _proposeReschedule(Map<String, dynamic> a) async {
    final hours = [
      '08:00 ص', '09:00 ص', '10:00 ص', '11:00 ص',
      '12:00 م', '01:00 م', '02:00 م', '03:00 م',
      '04:00 م', '05:00 م', '06:00 م', '07:00 م',
    ];
    String chosenHour = hours.first;
    DateTime chosenDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('اقتراح موعد بديل للزبون'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: chosenDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (d != null) setS(() => chosenDate = d);
                },
                child: Text('التاريخ: ${chosenDate.toString().split(' ').first}'),
              ),
              DropdownButton<String>(
                value: chosenHour,
                items: hours.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                onChanged: (v) => setS(() => chosenHour = v!),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final dateStr = chosenDate.toString().split(' ').first;
                await _db.from('workshop_appointments').update({
                  'status': 'reschedule_proposed',
                  'proposed_date': dateStr,
                  'proposed_time': chosenHour,
                }).eq('id', a['id']);
                await _notifs.sendNotification(
                  targetUserId: a['user_id'] as String,
                  title: 'تم اقتراح موعد بديل للورشة',
                  body: 'تقترح الورشة موعداً جديداً: $dateStr الساعة $chosenHour.',
                  type: 'reschedule_proposed',
                  referenceId: a['id'] as String,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('إرسال الاقتراح'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finishAndBill(Map<String, dynamic> a) async {
    if (!EnvConfig.paymentsEnabled.value) {
      await _db
          .from('workshop_appointments')
          .update({'status': 'completed', 'progress_step': 'completed'})
          .eq('id', a['id']);
      await _notifs.sendNotification(
        targetUserId: a['user_id'] as String,
        title: 'سيارتك جاهزة للتسليم!',
        body: 'انتهى تصليح السيارة في الورشة ويمكنك استلامها الآن.',
        type: 'car_ready',
        referenceId: a['id'] as String,
      );
      return;
    }

    final existingAmt = ((a['total_amount'] as num?) ?? 0).toDouble();
    final amountCtrl = TextEditingController(
      text: existingAmt > 0 ? existingAmt.toStringAsFixed(2) : '',
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء الصيانة وإصدار الفاتورة'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'أدخل المبلغ المطلوب (د.أ)'),
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
              await _db.from('workshop_appointments').update({
                'total_amount': amt,
                'progress_step': 'awaiting_payment',
                'payment_status': 'unpaid',
              }).eq('id', a['id']);
              await _notifs.sendNotification(
                targetUserId: a['user_id'] as String,
                title: 'سيارتك جاهزة للتسليم!',
                body: 'انتهى تصليح السيارة، قيمة الفاتورة ${amt.toStringAsFixed(2)} د.أ.',
                type: 'car_ready',
                referenceId: a['id'] as String,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('إرسال الفاتورة للزبون'),
          ),
        ],
      ),
    );
    amountCtrl.dispose();
  }

  Widget _buildWalletTab() {
    final txs = _walletTxs.where((t) => _inPeriodDate(t.createdAt)).toList();
    final periodGross = txs.fold(0.0, (s, t) => s + t.grossAmount);
    final periodComm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
    final periodNet = txs.fold(0.0, (s, t) => s + t.netAmount);
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
          Card(
            color: AppColors.navy,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'صافي الرصيد في المحفظة (بعد العمولة)',
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
                  const SizedBox(height: 10),
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
                    'قبل العمولة: ${periodGross.toStringAsFixed(2)} د.أ  |  العمولات: ${periodComm.toStringAsFixed(2)} د.أ',
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
          ),
          const SizedBox(height: 16),
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
                      '${_txArabicType(t.transactionType)} · ${_paymentMethodArabic(t.paymentMethod)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      'قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} د.أ | العمولة: -${t.commissionAmount.toStringAsFixed(2)} د.أ',
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

  String _txArabicType(String raw) => switch (raw.toLowerCase()) {
        'order' || 'part_order' => 'بيع قطعة غيار',
        'workshop' || 'appointment' => 'خدمة ورشة',
        'winch_towing' || 'winch' || 'emergency' => 'طلب طوارئ / ونش',
        _ => raw,
      };

  String _paymentMethodArabic(String raw) => switch (raw.toLowerCase()) {
        'cash' => 'نقداً (كاش)',
        'apple_pay' => 'Apple Pay',
        'google_pay' => 'Google Pay',
        'visa' || 'card' || 'meps' => 'فيزا / ماستركارد',
        _ => raw,
      };
}