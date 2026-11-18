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
  final _notifs = NotificationsService();
  final _tracker = LiveProgressTracker.instance;
  final _locationService = LocationService();

  late int _tab = widget.initialTab;
  late bool _isAvailable = widget.profile.isAvailable;
  late double? _myLat = widget.profile.latitude ?? widget.profile.workshopLatitude;
  late double? _myLng = widget.profile.longitude ?? widget.profile.workshopLongitude;
  final double _maxRadiusKm = 15.0;

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
    _syncProviderGps();
  }

  Future<void> _syncProviderGps() async {
    try {
      final res = await _locationService.getCurrentLocation();
      if (!mounted) {
        return;
      }
      setState(() {
        _myLat = res.coordinates.latitude;
        _myLng = res.coordinates.longitude;
      });
      await _db.from('customers').update({'latitude': _myLat, 'longitude': _myLng}).eq('id', widget.profile.id);
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
    return Geolocator.distanceBetween(_myLat!, _myLng!, r.pickupLatitude!, r.pickupLongitude!) / 1000.0;
  }

  bool _isVisibleToMe(DbMechanicRequest r) {
    if (r.mechanicId == widget.profile.id) {
      return true;
    }
    if (!_isAvailable || r.status != 'pending') {
      return false;
    }
    if (r.broadcastAll) {
      return true;
    }
    final dist = _distanceToRequest(r);
    return dist == null || dist <= _maxRadiusKm;
  }

  Future<void> _openGpsNavigation(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    await launchUrl(url, mode: LaunchMode.externalApplication);
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
      Navigator.pushReplacement(context, animatedRoute(LiveMobileShell(profile: widget.profile, onRefreshProfile: widget.onRefreshProfile, onSignedOut: widget.onSignedOut)));
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
              title: Text(widget.profile.fullName ?? 'لوحة الورشة', style: const TextStyle(color: Colors.white, fontSize: 16)),
              actions: [
                IconButton(tooltip: 'العودة للرئيسية', icon: const Icon(Icons.storefront), onPressed: _goHome),
                const NotificationBellButton(),
                IconButton(
                  icon: const Icon(Icons.logout),
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
          if (isWide) SizedBox(width: 240, child: _buildSidebar(isDrawer: false)),
          Expanded(
            child: Column(
              children: [
                // شريط متاح / غير متاح + جرس الإشعارات للشاشات العريضة
                Container(
                  color: _isAvailable ? AppColors.success.withValues(alpha: 0.10) : Colors.red.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _isAvailable ? 'حالة الورشة: متاح لاستقبال الطلبات والمواعيد' : 'حالة الورشة: غير متاح حالياً',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _isAvailable ? AppColors.success : Colors.red),
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
                        3 => const MerchantProductsDashboard(),
                        4 => _buildWalletTab(),
                        5 => ProviderSubscriptionsScreen(currentPlanCode: widget.profile.subscriptionPlan, onSubscribed: widget.onRefreshProfile),
                        _ => _buildOverviewTab(),
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
              Expanded(child: Text(widget.profile.fullName ?? 'اسم النشاط', overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
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
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.storefront, color: Colors.white70), title: const Text('العودة للرئيسية (المتجر)', style: TextStyle(color: Colors.white70, fontSize: 13)), onTap: () => _goHome(closeDrawerFirst: isDrawer)),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          ...items.map((item) {
            final active = _tab == item.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _tab = item.id);
                  if (isDrawer) {
                    Navigator.pop(context);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: active ? AppColors.orange : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Text(item.label, style: TextStyle(color: active ? Colors.white : Colors.white70, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('mechanic_requests').stream(primaryKey: ['id']).order('created_at', ascending: false),
      builder: (context, reqSnap) {
        final reqs = (reqSnap.data ?? []).map(DbMechanicRequest.fromMap).where((r) => (showWinch || r.serviceType != 'winch') && _isVisibleToMe(r)).toList();
        final activeEmergencies = reqs.where((r) => r.status != 'completed').length;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _db.from('workshop_appointments').stream(primaryKey: ['id']).eq('workshop_id', widget.profile.id).order('created_at', ascending: false),
          builder: (context, apptSnap) {
            final appts = apptSnap.data ?? [];
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('نظرة عامة على اليوم', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white), onPressed: () => Navigator.push(context, animatedRoute(const AddProductScreen())), icon: const Icon(Icons.add, size: 18), label: const Text('إضافة قطعة')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth > 700 ? (showPayments ? 4 : 3) : 2;
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: cols >= 3 ? 1.85 : 1.55,
                        children: [
                          _kpiCard('طلبات طوارئ نشطة', '$activeEmergencies'),
                          _kpiCard('حجوزات الورشة اليوم', '${appts.length}'),
                          _kpiCard('سعة الورشة القصوى', '${widget.profile.maxCarCapacity}'),
                          if (showPayments) _kpiCard('رصيد المحفظة (د.أ)', widget.profile.walletBalance.toStringAsFixed(1)),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('طلبات الطوارئ المباشرة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              const DataColumn(label: Text('الطلب')),
                              const DataColumn(label: Text('النوع')),
                              const DataColumn(label: Text('المسافة')),
                              if (showPayments) const DataColumn(label: Text('المبلغ')),
                              const DataColumn(label: Text('الحالة')),
                            ],
                            rows: reqs.take(5).map((r) {
                              final d = _distanceToRequest(r);
                              return DataRow(cells: [
                                DataCell(Text('#${r.id.substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(r.serviceType == 'winch' ? 'ونش' : 'ميكانيكي')),
                                DataCell(Text(d != null ? '${d.toStringAsFixed(1)} كم' : '-')),
                                if (showPayments) DataCell(Text('${r.totalAmount} د.أ')),
                                DataCell(_statusBadge(r.status)),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _bottomCard(
                    'مواعيد الورشة القادمة',
                    appts.isEmpty
                        ? [const Text('لا توجد مواعيد حالياً')]
                        : appts.take(4).map((a) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${a['appointment_time']} · ${a['appointment_date']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(a['service_description'] ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                                ],
                              ),
                            )).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _kpiCard(String title, String val) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    if (status == 'accepted') {
      return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)), child: const Text('في الطريق', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)));
    }
    if (status == 'pending') {
      return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.orange)), child: const Text('بانتظار التعيين', style: TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.bold)));
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: AppColors.placeholder, borderRadius: BorderRadius.circular(20)), child: const Text('مكتمل', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)));
  }

  Widget _bottomCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 12), ...children]),
    );
  }

  Widget _buildEmergencyTab() {
    final showPayments = EnvConfig.paymentsEnabled.value;
    final showWinch = EnvConfig.winchEnabled.value;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('mechanic_requests').stream(primaryKey: ['id']).order('created_at', ascending: false),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final reqs = snap.data!.map(DbMechanicRequest.fromMap).where((r) {
          if (r.serviceType == 'winch' && (!showWinch || !widget.profile.hasTowing)) {
            return false;
          }
          return _isVisibleToMe(r);
        }).toList();

        if (reqs.isEmpty) {
          return Center(child: Text(_isAvailable ? 'لا توجد طلبات طوارئ متاحة حالياً' : 'أنت في وضع غير متاح — فعّل التوفر لاستقبال الطلبات'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reqs.length,
          itemBuilder: (_, i) {
            final r = reqs[i];
            final distKm = _distanceToRequest(r);
            final hasCoords = r.pickupLatitude != null && r.pickupLongitude != null;

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
                        Expanded(child: Text('${r.serviceType == 'winch' ? 'طلب ونش' : 'ميكانيكي طوارئ'} · ${r.carDetails}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                        if (distKm != null)
                          Chip(backgroundColor: AppColors.orangeLight, label: Text('يبعد ${distKm.toStringAsFixed(1)} كم', style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 11))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('المشكلة: ${r.description ?? "-"} · الهاتف: ${r.phone ?? "-"}'),
                    Text('العنوان: ${r.dropoffAddress ?? "موقع العميل"}'),
                    if (r.broadcastAll && r.status == 'pending')
                      const Text('تنبيه: لا يوجد مزود ضمن 15 كم، تم إرسال الطلب للجميع', style: TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                    if (showPayments) Text('المبلغ: ${r.totalAmount} د.أ'),
                    const SizedBox(height: 10),
                    if (hasCoords) ...[
                      SizedBox(
                        height: 140,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FlutterMap(
                            options: MapOptions(initialCenter: LatLng(r.pickupLatitude!, r.pickupLongitude!), initialZoom: 14),
                            children: [
                              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.autoparts.app'),
                              MarkerLayer(markers: [Marker(point: LatLng(r.pickupLatitude!, r.pickupLongitude!), width: 44, height: 44, child: const Icon(Icons.location_on, color: AppColors.orange, size: 38))]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.navy), padding: const EdgeInsets.symmetric(vertical: 11)),
                          onPressed: () => _openGpsNavigation(r.pickupLatitude!, r.pickupLongitude!),
                          icon: const Icon(Icons.navigation, color: AppColors.navy),
                          label: const Text('توجيه GPS لموقع العميل', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (r.status == 'pending')
                      SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: () => _acceptEmergency(r), child: const Text('قبول الطلب والانطلاق'))),
                    if (r.status == 'accepted' && r.mechanicId == widget.profile.id)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (r.progressStep == 'on_the_way')
                            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white), onPressed: () { if (r.userId != null) { _tracker.markEmergencyArrived(requestId: r.id, customerUserId: r.userId!, serviceType: r.serviceType); } }, child: const Text('تأكيد الوصول للعميل')),
                          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white), onPressed: () async { await _db.from('mechanic_requests').update({'status': 'completed', 'progress_step': 'completed'}).eq('id', r.id); }, child: const Text('إنهاء الطلب')),
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

  Future<void> _acceptEmergency(DbMechanicRequest r) async {
    double? finalDropLat = r.dropoffLatitude;
    double? finalDropLng = r.dropoffLongitude;
    String? finalDropAddr = r.dropoffAddress;

    if (EnvConfig.winchEnabled.value && r.serviceType == 'winch' && widget.profile.hasTowing && widget.profile.workshopLatitude != null) {
      final goMyWorkshop = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('وجهة الونش'),
          content: const Text('هل تريد الذهاب بالسيارة إلى ورشتك أم إلى لوكيشن العميل (Drop-off)؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لوكيشن العميل')),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('إلى ورشتي')),
          ],
        ),
      );
      if (goMyWorkshop == null) {
        return;
      }
      if (goMyWorkshop) {
        finalDropLat = widget.profile.workshopLatitude;
        finalDropLng = widget.profile.workshopLongitude;
        finalDropAddr = widget.profile.workshopAddress ?? 'ورشة المزود';
      }
    }

    await _db.from('mechanic_requests').update({'status': 'accepted', 'progress_step': 'on_the_way', 'mechanic_id': widget.profile.id, 'dropoff_latitude': finalDropLat, 'dropoff_longitude': finalDropLng, 'dropoff_address': finalDropAddr}).eq('id', r.id);

    if (r.userId != null) {
      await _notifs.sendNotification(targetUserId: r.userId!, title: 'تم قبول طلب الطوارئ', body: 'المزود في طريقه إليك الآن.', type: 'order_accepted', referenceId: r.id);
      if (r.pickupLatitude != null && r.pickupLongitude != null) {
        await _tracker.startTrackingEmergencyArrival(requestId: r.id, customerUserId: r.userId!, serviceType: r.serviceType, pickupLat: r.pickupLatitude!, pickupLng: r.pickupLongitude!);
      }
    }
  }

  Widget _buildAppointmentsTab() {
    final showPayments = EnvConfig.paymentsEnabled.value;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('workshop_appointments').stream(primaryKey: ['id']).eq('workshop_id', widget.profile.id).order('created_at', ascending: false),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const Center(child: Text('لا توجد مواعيد محجوزة حالياً'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final a = list[i];
            final date = a['appointment_date'] as String;
            final acceptedOnDate = list.where((x) => x['appointment_date'] == date && x['status'] == 'accepted').length;
            final isFull = acceptedOnDate >= widget.profile.maxCarCapacity;
            final step = a['progress_step'] as String? ?? 'pending';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a['appointment_date']} · ${a['appointment_time']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(a['service_description'] ?? ''),
                    Text('الحالة: ${a['status']} | المرحلة: $step', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 10),
                    if (a['status'] == 'pending')
                      Row(
                        children: [
                          if (!isFull)
                            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white), onPressed: () => _acceptAppointment(a), child: const Text('قبول الموعد'))
                          else
                            const Text('الورشة مكتملة!', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          OutlinedButton(onPressed: () => _proposeReschedule(a), child: const Text('اقتراح موعد آخر')),
                        ],
                      ),
                    if (a['status'] == 'accepted') ...[
                      const Divider(),
                      Wrap(
                        spacing: 6,
                        children: [
                          _stepBtn(a, 'diagnosis', 'فحص'),
                          _stepBtn(a, 'repairing', 'قيد الإصلاح'),
                          _stepBtn(a, 'testing', 'فحص نهائي'),
                          ActionChip(backgroundColor: AppColors.orange, label: Text(showPayments ? 'جاهزة للتسليم + فاتورة' : 'جاهزة للتسليم', style: const TextStyle(color: Colors.white)), onPressed: () => _finishAndBill(a)),
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
        await _db.from('workshop_appointments').update({'progress_step': stepKey}).eq('id', appt['id']);
      },
    );
  }

  Future<void> _acceptAppointment(Map<String, dynamic> a) async {
    await _db.from('workshop_appointments').update({'status': 'accepted', 'progress_step': 'on_the_way'}).eq('id', a['id']);
    await _notifs.sendNotification(targetUserId: a['user_id'], title: 'تم قبول موعد الورشة', body: 'موعدك مؤكد بتاريخ ${a['appointment_date']} الساعة ${a['appointment_time']}.', type: 'order_accepted', referenceId: a['id']);
  }

  Future<void> _proposeReschedule(Map<String, dynamic> a) async {
    final hours = ['09:00 ص', '10:00 ص', '11:00 ص', '01:00 م', '03:00 م', '05:00 م'];
    String chosenHour = hours.first;
    DateTime chosenDate = DateTime.now().add(const Duration(days: 1));
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('اقتراح موعد بديل للزبون'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: chosenDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30))); if (d != null) { setS(() => chosenDate = d); } }, child: Text('التاريخ: ${chosenDate.toString().split(' ').first}')),
              DropdownButton<String>(value: chosenHour, items: hours.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(), onChanged: (v) => setS(() => chosenHour = v!)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final dateStr = chosenDate.toString().split(' ').first;
                await _db.from('workshop_appointments').update({'status': 'reschedule_proposed', 'proposed_date': dateStr, 'proposed_time': chosenHour}).eq('id', a['id']);
                await _notifs.sendNotification(targetUserId: a['user_id'], title: 'تم اقتراح موعد بديل للورشة', body: 'تقترح الورشة موعداً جديداً: $dateStr الساعة $chosenHour. يرجى القبول أو الرفض.', type: 'reschedule_proposed', referenceId: a['id']);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
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
      await _db.from('workshop_appointments').update({'status': 'completed', 'progress_step': 'completed'}).eq('id', a['id']);
      await _notifs.sendNotification(targetUserId: a['user_id'], title: 'سيارتك جاهزة للتسليم!', body: 'انتهى تصليح السيارة في الورشة ويمكنك استلامها الآن.', type: 'car_ready', referenceId: a['id']);
      return;
    }
    final amountCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء الصيانة وإصدار الفاتورة'),
        content: TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أدخل المبلغ المطلوب (د.أ)')),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange, foregroundColor: Colors.white),
            onPressed: () async {
              final amt = double.tryParse(amountCtrl.text) ?? 0.0;
              if (amt <= 0) {
                return;
              }
              await _db.from('workshop_appointments').update({'total_amount': amt, 'progress_step': 'awaiting_payment'}).eq('id', a['id']);
              await _notifs.sendNotification(targetUserId: a['user_id'], title: 'سيارتك جاهزة للتسليم!', body: 'انتهى تصليح السيارة، قيمة الفاتورة $amt د.أ. يمكنك الدفع الآن عبر MEPS.', type: 'car_ready', referenceId: a['id']);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('إرسال الفاتورة للزبون'),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db.from('wallet_transactions').stream(primaryKey: ['id']).eq('provider_id', widget.profile.id).order('created_at', ascending: false),
      builder: (context, snap) {
        final txs = (snap.data ?? []).map(DbWalletTransaction.fromMap).toList();
        final gross = txs.fold(0.0, (s, t) => s + t.grossAmount);
        final comm = txs.fold(0.0, (s, t) => s + t.commissionAmount);
        final net = txs.fold(0.0, (s, t) => s + t.netAmount);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(color: AppColors.navy, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('صافي الرصيد في المحفظة (بعد العمولة)', style: TextStyle(color: Colors.white70)), const SizedBox(height: 6), Text('${net.toStringAsFixed(2)} د.أ', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 10), Text('إجمالي المبيعات (قبل العمولة): ${gross.toStringAsFixed(2)} د.أ  |  العمولات: ${comm.toStringAsFixed(2)} د.أ', style: const TextStyle(color: Colors.white70, fontSize: 12))]))),
            const SizedBox(height: 16),
            ...txs.map((t) => Card(child: ListTile(title: Text('${t.transactionType} · ${t.paymentMethod}'), subtitle: Text('قبل العمولة: ${t.grossAmount.toStringAsFixed(2)} | العمولة: -${t.commissionAmount.toStringAsFixed(2)}'), trailing: Text('+${t.netAmount.toStringAsFixed(2)} د.أ', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 15))))),
          ],
        );
      },
    );
  }
}