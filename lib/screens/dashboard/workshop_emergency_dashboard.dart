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
  State<WorkshopEmergencyDashboard> createState() =>
      _WorkshopEmergencyDashboardState();
}

class _WorkshopEmergencyDashboardState
    extends State<WorkshopEmergencyDashboard> {
  final _db = Supabase.instance.client;
  final _notifs = NotificationsService.instance;
  final _tracker = LiveProgressTracker.instance;
  final _locationService = LocationService();
  final _loc = AppLocaleService.instance;

  late int _tab = widget.initialTab;
  late bool _isAvailable = widget.profile.isAvailable;
  late double? _myLat =
      widget.profile.latitude ?? widget.profile.workshopLatitude;
  late double? _myLng =
      widget.profile.longitude ?? widget.profile.workshopLongitude;
  final double _maxRadiusKm = 15.0;
  DashboardPeriod _period = DashboardPeriod.month1;
  DateTimeRange? _customRange;
  final Set<String> _trackingEmergencyIds = {};

  List<({int id, String label})> get _menuItems {
    final list = <({int id, String label})>[
      (id: 0, label: _loc.tr('نظرة عامة', 'Overview')),
      (id: 1, label: _loc.tr('طلبات الطوارئ', 'Emergency Orders')),
      (id: 2, label: _loc.tr('حجوزات الورشة', 'Appointments')),
      (id: 3, label: _loc.tr('قطع الغيار والمخزون', 'Spare Parts')),
    ];
    if (EnvConfig.paymentsEnabled.value) {
      list.add((id: 4, label: _loc.tr('المحفظة المالية', 'Wallet')));
    }
    if (EnvConfig.subscriptionsEnabled.value) {
      list.add((id: 5, label: _loc.tr('الاشتراك والباقة', 'Subscription')));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _syncProviderGps();
  }

  bool _inPeriod(String? createdAt) {
    final dt = DateTime.tryParse(createdAt ?? '');
    if (dt == null) return true;
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) &&
        !dt.isAfter(range.end.add(const Duration(days: 1)));
  }

  Future<void> _syncProviderGps() async {
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

  double? _distanceToRequest(DbMechanicRequest r) {
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
    final dist = _distanceToRequest(r);
    return dist == null || dist <= _maxRadiusKm;
  }

  void _ensureLiveBroadcastForAccepted(DbMechanicRequest r) {
    if (r.mechanicId != widget.profile.id ||
        r.status != 'accepted' ||
        r.progressStep != 'on_the_way' ||
        r.userId == null ||
        r.pickupLatitude == null ||
        r.pickupLongitude == null) {
      return;
    }
    if (_trackingEmergencyIds.contains(r.id)) return;
    _trackingEmergencyIds.add(r.id);
    _tracker.startTrackingEmergencyArrival(
      requestId: r.id,
      customerUserId: r.userId!,
      serviceType: r.serviceType,
      pickupLat: r.pickupLatitude!,
      pickupLng: r.pickupLongitude!,
    );
  }

  Future<void> _openGpsNavigation(double lat, double lng) async {
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
    final showSubs = EnvConfig.subscriptionsEnabled.value;
    if (!showPayments && _tab == 4) _tab = 0;
    if (!showSubs && _tab == 5) _tab = 0;

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
                widget.profile.fullName ?? _loc.tr('لوحة الورشة', 'Workshop'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              actions: [
                IconButton(
                  tooltip: _loc.tr('العودة للرئيسية', 'Home'),
                  icon: const Icon(Icons.storefront, color: Colors.white),
                  onPressed: _goHome,
                ),
                const NotificationBellButton(iconColor: Colors.white),
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
      drawer: isWide ? null : Drawer(child: _buildSidebar(isDrawer: true)),
      body: Row(
        children: [
          if (isWide)
            SizedBox(width: 240, child: _buildSidebar(isDrawer: false)),
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
                                ? _loc.tr(
                                    'حالة الورشة: متاح لاستقبال الطلبات والمواعيد',
                                    'Workshop Status: Online & Available',
                                  )
                                : _loc.tr(
                                    'حالة الورشة: غير متاح حالياً',
                                    'Workshop Status: Offline',
                                  ),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color:
                                  _isAvailable ? AppColors.success : Colors.red,
                            ),
                          ),
                          value: _isAvailable,
                          activeTrackColor: AppColors.success,
                          onChanged: _toggleAvailability,
                        ),
                      ),
                      if (isWide)
                        const NotificationBellButton(iconColor: AppColors.navy),
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
                        3 => const MerchantProductsDashboard(),
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
    return Material(
      color: AppColors.navy,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.profile.fullName ?? _loc.tr('اسم النشاط', 'Workshop'),
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
                    await _db.auth.signOut();
                    if (mounted) {
                      Navigator.popUntil(context, (r) => r.isFirst);
                    }
                    widget.onSignedOut();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront, color: Colors.white),
              title: Text(
                _loc.tr('العودة للرئيسية (المتجر)', 'Back to Store Home'),
                style: const TextStyle(color: Colors.white, fontSize: 13),
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
                    if (isDrawer) Navigator.pop(context);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: active ? AppColors.orange : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white70,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(bool isWide) {
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('mechanic_requests')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false),
      builder: (context, reqSnap) {
        final rawReqs = (reqSnap.data ?? [])
            .where((r) => _inPeriod(r['created_at'] as String?))
            .toList();
        final reqs = rawReqs
            .map(DbMechanicRequest.fromMap)
            .where((r) =>
                (showWinch || r.serviceType != 'winch') && _isVisibleToMe(r))
            .toList();
        final activeEmergencies =
            reqs.where((r) => r.status != 'completed' && r.status != 'cancelled').length;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db
              .from('workshop_appointments')
              .stream(primaryKey: ['id'])
              .eq('workshop_id', widget.profile.id)
              .order('created_at', ascending: false),
          builder: (context, apptSnap) {
            final appts = (apptSnap.data ?? [])
                .where((a) => _inPeriod(a['created_at'] as String?))
                .toList();
            final completedAppts =
                appts.where((a) => a['status'] == 'completed').length;
            final pendingAppts =
                appts.where((a) => a['status'] == 'pending').length;

            final chartData = [
              (
                label: _loc.tr('طوارئ نشطة', 'Active SOS'),
                value: activeEmergencies.toDouble()
              ),
              (
                label: _loc.tr('كل المواعيد', 'All Bookings'),
                value: appts.length.toDouble()
              ),
              (
                label: _loc.tr('قيد الانتظار', 'Pending'),
                value: pendingAppts.toDouble()
              ),
              (
                label: _loc.tr('مكتملة', 'Completed'),
                value: completedAppts.toDouble()
              ),
            ];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _loc.tr('نظرة عامة', 'Overview'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.push(
                            context, animatedRoute(const AddProductScreen())),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(_loc.tr('إضافة قطعة', 'Add Part')),
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
                      _kpiCard(_loc.tr('طلبات طوارئ نشطة', 'Active SOS'),
                          activeEmergencies, Icons.car_crash),
                      _kpiCard(_loc.tr('حجوزات الورشة', 'Bookings'),
                          appts.length, Icons.event_available),
                      _kpiCard(_loc.tr('سعة الورشة القصوى', 'Max Capacity'),
                          widget.profile.maxCarCapacity, Icons.garage),
                      if (showPayments)
                        _kpiCard(
                          _loc.tr('رصيد المحفظة (د.أ)', 'Wallet (JOD)'),
                          widget.profile.walletBalance.toInt(),
                          Icons.account_balance_wallet,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  InteractiveAnimatedChart(
                    title: _loc.tr(
                      'إحصائيات الورشة والطوارئ التفاعلية',
                      'Workshop & Emergency Analytics',
                    ),
                    data: chartData,
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
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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

  Widget _buildEmergencyTab() {
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('mechanic_requests')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final reqs = snap.data!
            .where((r) => _inPeriod(r['created_at'] as String?))
            .map(DbMechanicRequest.fromMap)
            .where((r) =>
                (r.serviceType != 'winch' ||
                    (showWinch && widget.profile.hasTowing)) &&
                _isVisibleToMe(r))
            .toList();

        if (reqs.isEmpty) {
          return Center(
            child: Text(_isAvailable
                ? _loc.tr('لا توجد طلبات طوارئ متاحة حالياً',
                    'No emergency requests available')
                : _loc.tr('أنت في وضع غير متاح', 'You are currently offline')),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reqs.length,
          itemBuilder: (_, i) {
            final r = reqs[i];
            _ensureLiveBroadcastForAccepted(r);
            final distKm = _distanceToRequest(r);
            final hasCoords =
                r.pickupLatitude != null && r.pickupLongitude != null;

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
                            '${r.serviceType == 'winch' ? _loc.tr('طلب ونش', 'Winch') : _loc.tr('ميكانيكي طوارئ', 'Roadside')} · ${r.carDetails}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        if (distKm != null)
                          Chip(
                            backgroundColor: AppColors.orangeLight,
                            label: Text(
                              _loc.tr('يبعد ${distKm.toStringAsFixed(1)} كم',
                                  '${distKm.toStringAsFixed(1)} km away'),
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
                      '${_loc.tr("المشكلة", "Issue")}: ${r.description ?? "-"} · ${_loc.tr("الهاتف", "Phone")}: ${r.phone ?? "-"}',
                    ),
                    Text(
                      '${_loc.tr("العنوان", "Location")}: ${r.dropoffAddress ?? _loc.tr("موقع العميل", "Customer GPS")}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (r.quotedPrice > 0 || r.totalAmount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_loc.tr("عرض السعر / الفاتورة", "Quote / Invoice")}: ${(r.totalAmount > 0 ? r.totalAmount : r.quotedPrice).toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
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
                          borderRadius: BorderRadius.circular(14),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter:
                                  LatLng(r.pickupLatitude!, r.pickupLongitude!),
                              initialZoom: 14,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                                subdomains: const ['a', 'b', 'c', 'd'],
                                userAgentPackageName: 'com.autoparts.ghiyarak',
                                retinaMode: true,
                              ),
                              MarkerLayer(markers: [
                                Marker(
                                  point: LatLng(
                                      r.pickupLatitude!, r.pickupLongitude!),
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
                              side: const BorderSide(color: AppColors.navy)),
                          onPressed: () => _openGpsNavigation(
                              r.pickupLatitude!, r.pickupLongitude!),
                          icon: const Icon(Icons.navigation,
                              color: AppColors.navy),
                          label: Text(
                            _loc.tr('توجيه GPS لموقع العميل',
                                'Navigate to Customer (GPS)'),
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (r.status == 'pending')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => _sendEmergencyQuoteDialog(r),
                          icon: const Icon(Icons.request_quote_rounded),
                          label: Text(_loc.tr(
                            'قبول وإرسال عرض سعر للزبون',
                            'Accept & Send Price Quote',
                          )),
                        ),
                      ),
                    if (r.status == 'quote_sent' &&
                        r.mechanicId == widget.profile.id)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.orangeLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _loc.tr(
                            'تم إرسال عرض السعر (${r.quotedPrice.toStringAsFixed(2)} د.أ) — بانتظار موافقة الزبون...',
                            'Quote (${r.quotedPrice.toStringAsFixed(2)} JOD) sent — awaiting customer decision...',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                    if (r.status == 'accepted' &&
                        r.mechanicId == widget.profile.id)
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
                              onPressed: () async {
                                if (r.userId != null) {
                                  await _tracker.markEmergencyArrived(
                                    requestId: r.id,
                                    customerUserId: r.userId!,
                                    serviceType: r.serviceType,
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppColors.success,
                                        content: Text(_loc.tr(
                                          'تم تأكيد وصولك وإشعار العميل ✓',
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
                          if (r.progressStep != 'awaiting_payment')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () =>
                                  _issueEmergencyInvoiceDialog(r, showPayments),
                              icon: const Icon(Icons.receipt_long, size: 17),
                              label: Text(
                                showPayments
                                    ? _loc.tr('إصدار وتسليم الفاتورة',
                                        'Issue Final Invoice')
                                    : _loc.tr('إنهاء الطلب', 'Finish Job'),
                              ),
                            )
                          else
                            Chip(
                              backgroundColor:
                                  AppColors.success.withValues(alpha: 0.14),
                              label: Text(
                                _loc.tr(
                                  'تم إصدار الفاتورة ✓ بانتظار دفع العميل',
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
          },
        );
      },
    );
  }

  /// إرسال عرض سعر للزبون بدل تسعيرة العداد
  Future<void> _sendEmergencyQuoteDialog(DbMechanicRequest r) async {
    final priceCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool sending = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(_loc.tr('إرسال عرض سعر للزبون', 'Send Price Quote')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                enabled: !sending,
                decoration: InputDecoration(
                  labelText: _loc.tr('السعر المقترح (د.أ)', 'Quoted Price (JOD)'),
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                enabled: !sending,
                decoration: InputDecoration(
                  labelText: _loc.tr(
                    'ملاحظات / وقت الوصول المتوقع (اختياري)',
                    'Notes / ETA (optional)',
                  ),
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
                      if (price <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red,
                            content: Text(_loc.tr(
                              'يرجى إدخال سعر صحيح أكبر من صفر',
                              'Enter a valid price greater than 0',
                            )),
                          ),
                        );
                        return;
                      }
                      setS(() => sending = true);
                      try {
                        await _db.from('mechanic_requests').update({
                          'status': 'quote_sent',
                          'progress_step': 'pending',
                          'mechanic_id': widget.profile.id,
                          'quoted_price': price,
                          'total_amount': price,
                          'quote_notes': notesCtrl.text.trim(),
                        }).eq('id', r.id);

                        if (r.userId != null) {
                          await _notifs.sendNotification(
                            targetUserId: r.userId!,
                            title: 'وصلك عرض سعر لطلب الطوارئ 💰',
                            body:
                                'قدّم ${widget.profile.fullName ?? "المزود"} عرض سعر بقيمة ${price.toStringAsFixed(2)} د.أ — افتح التطبيق للقبول أو الرفض.',
                            type: 'quote_sent',
                            referenceId: r.id,
                          );
                        }

                        await _notifs.sendNotification(
                          targetUserId: widget.profile.id,
                          title: 'تم إرسال عرض السعر بنجاح ✓',
                          body:
                              'تم إرسال عرض بقيمة ${price.toStringAsFixed(2)} د.أ للزبون وبانتظار موافقته.',
                          type: 'quote_sent_confirm',
                          referenceId: r.id,
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.success,
                              content: Text(_loc.tr(
                                'تم إرسال عرض السعر للزبون بنجاح ✓',
                                'Price quote sent successfully ✓',
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
                              content: Text('$e'),
                            ),
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

  /// إصدار فاتورة طلب الطوارئ مع قفل التحميل وإشعار فوري للزبون والميكانيكي
  Future<void> _issueEmergencyInvoiceDialog(
    DbMechanicRequest r,
    bool showPayments,
  ) async {
    if (!showPayments) {
      await _db.from('mechanic_requests').update({
        'status': 'completed',
        'progress_step': 'completed',
      }).eq('id', r.id);
      if (r.userId != null) {
        await _notifs.sendNotification(
          targetUserId: r.userId!,
          title: 'تم إنهاء طلب الطوارئ بنجاح ✓',
          body: 'شكراً لاستخدامك غيارك! يمكنك الآن تقييم مقدم الخدمة.',
          type: 'order_completed',
          referenceId: r.id,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(_loc.tr('تم إنهاء الطلب بنجاح ✓', 'Job completed ✓')),
          ),
        );
      }
      return;
    }

    final initialAmt = r.totalAmount > 0 ? r.totalAmount : r.quotedPrice;
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
            'إصدار فاتورة الطوارئ وإرسالها للزبون',
            'Issue Emergency Invoice',
          )),
          content: TextField(
            controller: amountCtrl,
            enabled: !submitting,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _loc.tr('المبلغ النهائي المطلوب (د.أ)',
                  'Final Invoice Amount (JOD)'),
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
                        }).eq('id', r.id);

                        // إشعار فوري على هاتف الزبون
                        if (r.userId != null) {
                          await _notifs.sendNotification(
                            targetUserId: r.userId!,
                            title: 'تم إصدار الفاتورة — يرجى الدفع 🧾',
                            body:
                                'انتهت خدمة الطوارئ بقيمة ${amt.toStringAsFixed(2)} د.أ. يرجى إتمام الدفع الآن.',
                            type: 'invoice_issued',
                            referenceId: r.id,
                          );
                        }
                        // إشعار تأكيد فوري على هاتف الميكانيكي
                        await _notifs.sendNotification(
                          targetUserId: widget.profile.id,
                          title: 'تم إصدار الفاتورة بنجاح ✓',
                          body:
                              'تم إرسال فاتورة بقيمة ${amt.toStringAsFixed(2)} د.أ للزبون للدفع.',
                          type: 'invoice_issued_confirm',
                          referenceId: r.id,
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
                              content: Text('$e'),
                            ),
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
                  : Text(_loc.tr('إرسال الفاتورة الآن', 'Send Invoice')),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
  }

  Widget _buildAppointmentsTab() {
    final showPayments = EnvConfig.paymentsEnabled.value;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('workshop_appointments')
          .stream(primaryKey: ['id'])
          .eq('workshop_id', widget.profile.id)
          .order('created_at', ascending: false),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return Center(
            child: Text(_loc.tr('لا توجد مواعيد محجوزة حالياً',
                'No workshop appointments yet')),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final a = list[i];
            final date = a['appointment_date'] as String;
            final acceptedOnDate = list
                .where(
                    (x) => x['appointment_date'] == date && x['status'] == 'accepted')
                .length;
            final isFull = acceptedOnDate >= widget.profile.maxCarCapacity;
            final step = a['progress_step'] as String? ?? 'pending';
            final invoiceIssued = step == 'awaiting_payment' ||
                a['invoice_issued_at'] != null ||
                a['payment_status'] == 'paid';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${a['appointment_date']} · ${a['appointment_time']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(a['service_description'] ?? ''),
                    Text(
                      '${_loc.tr("الحالة", "Status")}: ${a['status']} | ${_loc.tr("المرحلة", "Step")}: $step',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
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
                              child: Text(_loc.tr('قبول الموعد', 'Accept')),
                            )
                          else
                            Text(
                              _loc.tr('الورشة ممتلئة لهذا اليوم!',
                                  'Workshop full for this day!'),
                              style: const TextStyle(
                                color: AppColors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          OutlinedButton(
                            onPressed: () => _proposeReschedule(a),
                            child: Text(_loc.tr(
                              'اقتراح موعد آخر',
                              'Propose New Time',
                            )),
                          ),
                        ],
                      ),
                    if (a['status'] == 'accepted') ...[
                      const Divider(),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _stepBtn(a, 'diagnosis', _loc.tr('فحص', 'Diagnosis')),
                          _stepBtn(
                              a, 'repairing', _loc.tr('قيد الإصلاح', 'Repair')),
                          _stepBtn(
                              a, 'testing', _loc.tr('فحص نهائي', 'Testing')),
                          if (!invoiceIssued)
                            ActionChip(
                              backgroundColor: AppColors.orange,
                              label: Text(
                                showPayments
                                    ? _loc.tr('جاهزة للتسليم + فاتورة',
                                        'Car Ready + Issue Invoice')
                                    : _loc.tr('جاهزة للتسليم', 'Car Ready'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () => _finishAndBill(a),
                            )
                          else
                            Chip(
                              backgroundColor:
                                  AppColors.success.withValues(alpha: 0.14),
                              label: Text(
                                _loc.tr(
                                  'تم إصدار الفاتورة ✓ (${a['total_amount'] ?? 0} د.أ)',
                                  'Invoice Issued ✓ (${a['total_amount'] ?? 0} JOD)',
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
      labelStyle:
          TextStyle(color: active ? Colors.white : AppColors.textPrimary),
      onSelected: (_) async {
        await _db
            .from('workshop_appointments')
            .update({'progress_step': stepKey}).eq('id', appt['id']);
        // إشعار العميل بتحديث مرحلة صيانة سيارته
        if (appt['user_id'] != null) {
          await _notifs.sendNotification(
            targetUserId: appt['user_id'],
            title: 'تحديث حالة صيانة سيارتك 🔧',
            body: 'المرحلة الحالية في الورشة: $label.',
            type: 'workshop_step',
            referenceId: appt['id'],
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.navy,
              content: Text(_loc.tr(
                'تم تحديث المرحلة إلى ($label) وإشعار العميل ✓',
                'Updated step to ($label) & notified customer ✓',
              )),
            ),
          );
        }
      },
    );
  }

  Future<void> _acceptAppointment(Map<String, dynamic> a) async {
    try {
      await _db.from('workshop_appointments').update({
        'status': 'accepted',
        'progress_step': 'on_the_way',
      }).eq('id', a['id']);

      await _notifs.sendNotification(
        targetUserId: a['user_id'],
        title: 'تم قبول موعد الورشة ✅',
        body:
            'موعدك مؤكد بتاريخ ${a['appointment_date']} الساعة ${a['appointment_time']}.',
        type: 'order_accepted',
        referenceId: a['id'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(_loc.tr(
                'تم قبول الموعد وإشعار العميل ✓', 'Appointment accepted ✓')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('$e')),
        );
      }
    }
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
          title: Text(_loc.tr('اقتراح موعد بديل للزبون', 'Propose New Slot')),
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
                child: Text(
                    '${_loc.tr("التاريخ", "Date")}: ${chosenDate.toString().split(' ').first}'),
              ),
              DropdownButton<String>(
                value: chosenHour,
                items: hours
                    .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                    .toList(),
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
                  targetUserId: a['user_id'],
                  title: 'تم اقتراح موعد بديل للورشة 📅',
                  body: 'تقترح الورشة موعداً جديداً: $dateStr الساعة $chosenHour.',
                  type: 'reschedule_proposed',
                  referenceId: a['id'],
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(_loc.tr('إرسال الاقتراح', 'Send Proposal')),
            ),
          ],
        ),
      ),
    );
  }

  /// إنهاء الصيانة وإصدار الفاتورة مع قفل التحميل وتأكيد وإشعارات للهاتف (الزبون + الميكانيكي)
  Future<void> _finishAndBill(Map<String, dynamic> a) async {
    if (!EnvConfig.paymentsEnabled.value) {
      await _db.from('workshop_appointments').update({
        'status': 'completed',
        'progress_step': 'completed',
      }).eq('id', a['id']);
      await _notifs.sendNotification(
        targetUserId: a['user_id'],
        title: 'سيارتك جاهزة للتسليم! 🚗',
        body: 'انتهى تصليح السيارة في الورشة ويمكنك استلامها الآن.',
        type: 'car_ready',
        referenceId: a['id'],
      );
      await _notifs.sendNotification(
        targetUserId: widget.profile.id,
        title: 'تم إنهاء الطلب بنجاح ✓',
        body: 'تم إشعار العميل بأن سيارته جاهزة للاستلام.',
        type: 'car_ready_confirm',
        referenceId: a['id'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(_loc.tr(
              'تم تأكيد جاهزية السيارة وإرسال الإشعار للعميل ✓',
              'Car marked ready & customer notified ✓',
            )),
          ),
        );
      }
      return;
    }

    final amountCtrl = TextEditingController();
    bool submitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(_loc.tr(
            'إنهاء الصيانة وإصدار الفاتورة',
            'Finish Repair & Issue Invoice',
          )),
          content: TextField(
            controller: amountCtrl,
            enabled: !submitting,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  _loc.tr('أدخل المبلغ المطلوب (د.أ)', 'Invoice Amount (JOD)'),
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
                      if (amt <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red,
                            content: Text(_loc.tr(
                              'يرجى إدخال مبلغ صحيح أكبر من صفر',
                              'Enter a valid invoice amount',
                            )),
                          ),
                        );
                        return;
                      }
                      setS(() => submitting = true);
                      try {
                        await _db.from('workshop_appointments').update({
                          'total_amount': amt,
                          'progress_step': 'awaiting_payment',
                          'invoice_issued_at':
                              DateTime.now().toIso8601String(),
                        }).eq('id', a['id']);

                        // إشعار فوري على هاتف الزبون
                        await _notifs.sendNotification(
                          targetUserId: a['user_id'],
                          title: 'تم إصدار الفاتورة — يرجى الدفع 🧾',
                          body:
                              'سيارتك جاهزة للتسليم! قيمة الفاتورة ${amt.toStringAsFixed(2)} د.أ — يرجى إتمام الدفع الآن.',
                          type: 'car_ready',
                          referenceId: a['id'],
                        );

                        // إشعار تأكيد فوري على هاتف الميكانيكي
                        await _notifs.sendNotification(
                          targetUserId: widget.profile.id,
                          title: 'تم إصدار الفاتورة بنجاح ✓',
                          body:
                              'تم إرسال فاتورة بقيمة ${amt.toStringAsFixed(2)} د.أ إلى العميل للدفع.',
                          type: 'invoice_issued_confirm',
                          referenceId: a['id'],
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.success,
                              content: Text(_loc.tr(
                                'تم إصدار الفاتورة بنجاح وإرسال إشعار للزبون للدفع ✓',
                                'Invoice issued successfully & customer notified ✓',
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
                              content: Text('$e'),
                            ),
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
                  : Text(_loc.tr('إرسال الفاتورة للزبون', 'Send Invoice')),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
  }

  Widget _buildWalletTab() {
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
        final gross = txs.fold(0.0, (s, t) => s + t.grossAmount);
        final comm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
        final net = txs.fold(0.0, (s, t) => s + t.netAmount);
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
            Card(
              color: AppColors.navy,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _loc.tr('صافي الرصيد في المحفظة (بعد العمولة)',
                          'Net Wallet Balance'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${net.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${_loc.tr("قبل العمولة", "Gross")}: ${gross.toStringAsFixed(2)} | ${_loc.tr("العمولات", "Fees")}: ${comm.toStringAsFixed(2)}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...txs.map((t) => Card(
                  child: ListTile(
                    title: Text('${t.transactionType} · ${t.paymentMethod}'),
                    subtitle: Text(
                      '${_loc.tr("الإجمالي", "Gross")}: ${t.grossAmount.toStringAsFixed(2)} | ${_loc.tr("العمولة", "Fee")}: -${t.commissionAmount.toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      '+${t.netAmount.toStringAsFixed(2)} ${_loc.tr("د.أ", "JOD")}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
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