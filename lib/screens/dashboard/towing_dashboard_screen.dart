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

  @override
  void initState() {
    super.initState();
    _syncGps();
  }

  bool _inPeriod(String? createdAt) {
    final dt = DateTime.tryParse(createdAt ?? '');
    if (dt == null) return true;
    final range = DateRangeFilterBar.resolveRange(_period, _customRange);
    return !dt.isBefore(range.start) && !dt.isAfter(range.end.add(const Duration(days: 1)));
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
    return Geolocator.distanceBetween(_myLat!, _myLng!, r.pickupLatitude!, r.pickupLongitude!) / 1000.0;
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
              onTap: (i) => setState(() => _tab = i),
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
      stream: _db
          .from('mechanic_requests')
          .stream(primaryKey: ['id'])
          .eq('service_type', 'winch')
          .order('created_at', ascending: false)
          .limit(100),
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
                        const SizedBox(height: 6),
                        Text('المشكلة: ${o.description ?? "-"} · الهاتف: ${o.phone ?? "-"}'),
                        Text(
                          'الوجهة: ${o.dropoffAddress ?? "محددة على الخريطة"}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (o.totalAmount > 0)
                          Text(
                            'الأجرة المقدّرة: ${o.totalAmount.toStringAsFixed(2)} د.أ',
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
                                      child: const Icon(Icons.location_on,
                                          color: AppColors.orange, size: 38),
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
                              onPressed: () => _openGpsNav(o.pickupLatitude!, o.pickupLongitude!),
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
                                child: const Text('تأكيد التسليم وإنهاء الطلب'),
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

  Future<void> _acceptWinch(DbMechanicRequest o) async {
    try {
      await _db
          .from('mechanic_requests')
          .update({'status': 'accepted', 'progress_step': 'on_the_way', 'mechanic_id': widget.profile.id})
          .eq('id', o.id)
          .select('id');
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

  Future<void> _completeWinch(DbMechanicRequest o, bool showPayments) async {
    try {
      final rate = widget.profile.commissionRate;
      final comm = showPayments ? o.totalAmount * rate : 0.0;
      final net = showPayments ? o.totalAmount - comm : 0.0;
      await _db.from('mechanic_requests').update({
        'status': 'completed',
        'progress_step': 'completed',
        'commission_amount': comm,
        'payment_status': 'paid',
      }).eq('id', o.id).select('id');
      _tracker.stop();

      if (showPayments) {
        await _db.from('wallet_transactions').insert({
          'provider_id': widget.profile.id,
          'customer_id': o.userId,
          'reference_id': o.id,
          'transaction_type': 'winch_towing',
          'payment_method': 'cash',
          'gross_amount': o.totalAmount,
          'commission_rate': rate,
          'commission_amount': comm,
          'net_amount': net,
          'status': 'completed',
        });
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
  }

  Widget _towingWalletTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _db
          .from('wallet_transactions')
          .stream(primaryKey: ['id'])
          .eq('provider_id', widget.profile.id)
          .order('created_at', ascending: false)
          .limit(50),
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
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('صافي محفظة الونش', style: TextStyle(color: Colors.white70)),
                  Text(
                    '${net.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'قبل العمولة: ${gross.toStringAsFixed(2)} | العمولة: ${comm.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...txs.map((t) => Card(
                  child: ListTile(
                    title: Text('رحلة ونش #${(t.referenceId != null && t.referenceId!.length >= 6) ? t.referenceId!.substring(0, 6) : ""}'),
                    subtitle: Text(
                      'قبل العمولة: ${t.grossAmount} · العمولة: -${t.commissionAmount.toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      '+${t.netAmount.toStringAsFixed(2)} د.أ',
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}