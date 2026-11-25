import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/db_models.dart';
import '../screens/mobile/workshop_checkout_screen.dart';
import '../services/app_locale_service.dart';
import '../services/dynamic_island_service.dart';
import '../services/live_progress_tracker.dart';
import '../services/notifications_service.dart';
import '../theme/app_theme.dart';
import 'animations.dart';

class HomeLiveProgressBanner extends StatefulWidget {
  final CustomerProfile? viewerProfile;

  const HomeLiveProgressBanner({super.key, required this.viewerProfile});

  @override
  State<HomeLiveProgressBanner> createState() => _HomeLiveProgressBannerState();
}

class _ProgressBannerItem {
  final String keyId;
  final bool isWorkshop;
  final bool isProviderSide;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  const _ProgressBannerItem({
    required this.keyId,
    required this.isWorkshop,
    required this.isProviderSide,
    required this.data,
    required this.createdAt,
  });
}

class _HomeLiveProgressBannerState extends State<HomeLiveProgressBanner> {
  final _db = Supabase.instance.client;
  final _tracker = LiveProgressTracker.instance;
  final _notifs = NotificationsService.instance;
  final _loc = AppLocaleService.instance;
  final PageController _pageController = PageController();

  final Set<String> _startedWorkshopTracking = {};
  final Set<String> _startedEmergencyTracking = {};
  final Set<String> _fetchingProviderIds = {};
  final Set<String> _cancellingIds = {};

  final Map<String, ({double? lat, double? lng, String address})>
      _workshopLocations = {};
  final Map<String, ({double? lat, double? lng, String name})>
      _providerLocations = {};

  StreamSubscription<List<Map<String, dynamic>>>? _custApptSub;
  StreamSubscription<List<Map<String, dynamic>>>? _custEmgSub;
  StreamSubscription<List<Map<String, dynamic>>>? _provApptSub;
  StreamSubscription<List<Map<String, dynamic>>>? _provEmgSub;

  List<Map<String, dynamic>> _custAppts = [];
  List<Map<String, dynamic>> _custEmgs = [];
  List<Map<String, dynamic>> _provAppts = [];
  List<Map<String, dynamic>> _provEmgs = [];

  String? _boundKey;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _bindStreams();
  }

  @override
  void didUpdateWidget(covariant HomeLiveProgressBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey =
        '${oldWidget.viewerProfile?.id}_${oldWidget.viewerProfile?.role}';
    final newKey = '${widget.viewerProfile?.id}_${widget.viewerProfile?.role}';
    if (oldKey != newKey) {
      _bindStreams();
    }
  }

  @override
  void dispose() {
    _cancelAllSubs();
    _pageController.dispose();
    super.dispose();
  }

  void _cancelAllSubs() {
    _custApptSub?.cancel();
    _custEmgSub?.cancel();
    _provApptSub?.cancel();
    _provEmgSub?.cancel();
    _custApptSub = null;
    _custEmgSub = null;
    _provApptSub = null;
    _provEmgSub = null;
  }

  void _bindStreams() {
    final viewer = widget.viewerProfile;
    final newKey = '${viewer?.id}_${viewer?.role}';
    if (_boundKey == newKey) return;
    _boundKey = newKey;

    _cancelAllSubs();
    _custAppts = [];
    _custEmgs = [];
    _provAppts = [];
    _provEmgs = [];

    if (viewer == null || viewer.id.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    final uid = viewer.id;
    final role = viewer.role;

    _custApptSub = _db
        .from('workshop_appointments')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() => _custAppts = rows);
          },
          onError: (_) {},
        );

    _custEmgSub = _db
        .from('mechanic_requests')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() => _custEmgs = rows);
          },
          onError: (_) {},
        );

    if (role == 'mechanic') {
      _provApptSub = _db
          .from('workshop_appointments')
          .stream(primaryKey: ['id'])
          .eq('workshop_id', uid)
          .order('created_at', ascending: false)
          .listen(
            (rows) {
              if (!mounted) return;
              setState(() => _provAppts = rows);
            },
            onError: (_) {},
          );
    }

    if (role == 'mechanic' || role == 'towing') {
      _provEmgSub = _db
          .from('mechanic_requests')
          .stream(primaryKey: ['id'])
          .eq('mechanic_id', uid)
          .order('created_at', ascending: false)
          .listen(
            (rows) {
              if (!mounted) return;
              setState(() => _provEmgs = rows);
            },
            onError: (_) {},
          );
    }
  }

  Future<void> _ensureWorkshopGps(
    Map<String, dynamic> appt, {
    required bool isProviderSide,
  }) async {
    final id = appt['id'] as String;
    final wId = appt['workshop_id'] as String?;
    if (wId == null) return;

    if (!_workshopLocations.containsKey(wId)) {
      if (_fetchingProviderIds.contains('w_$wId')) return;
      _fetchingProviderIds.add('w_$wId');
      try {
        final w = await _db
            .from('customers')
            .select(
              'workshop_latitude, workshop_longitude, latitude, longitude, street_name, workshop_address',
            )
            .eq('id', wId)
            .maybeSingle();

        final lat = (w?['workshop_latitude'] as num?)?.toDouble() ??
            (w?['latitude'] as num?)?.toDouble();
        final lng = (w?['workshop_longitude'] as num?)?.toDouble() ??
            (w?['longitude'] as num?)?.toDouble();
        final street = (w?['street_name'] as String?) ?? '';
        final addr = (w?['workshop_address'] as String?) ?? '';
        final fallbackAddr = street.isNotEmpty ? street : addr;

        if (mounted) {
          setState(() {
            _workshopLocations[wId] =
                (lat: lat, lng: lng, address: fallbackAddr);
          });
        }
      } catch (_) {} finally {
        _fetchingProviderIds.remove('w_$wId');
      }
    }

    if (!isProviderSide &&
        !_startedWorkshopTracking.contains(id) &&
        appt['status'] == 'accepted' &&
        appt['progress_step'] == 'on_the_way') {
      final loc = _workshopLocations[wId];
      if (loc?.lat != null && loc?.lng != null) {
        _startedWorkshopTracking.add(id);
        _tracker.startTrackingToWorkshop(
          appointmentId: id,
          workshopLat: loc!.lat!,
          workshopLng: loc.lng!,
          workshopUserId: wId,
        );
      }
    }
  }

  Future<void> _ensureEmergencyGps(
    Map<String, dynamic> emg, {
    required bool isProviderSide,
  }) async {
    final id = emg['id'] as String;
    final mechId = emg['mechanic_id'] as String?;
    final step = (emg['progress_step'] as String?) ?? 'pending';
    final status = (emg['status'] as String?) ?? 'pending';

    if (mechId != null &&
        mechId.isNotEmpty &&
        !_providerLocations.containsKey(mechId) &&
        !_fetchingProviderIds.contains('m_$mechId')) {
      _fetchingProviderIds.add('m_$mechId');
      try {
        final m = await _db
            .from('customers')
            .select(
                'latitude, longitude, workshop_latitude, workshop_longitude, full_name')
            .eq('id', mechId)
            .maybeSingle();
        final lat = (m?['latitude'] as num?)?.toDouble() ??
            (m?['workshop_latitude'] as num?)?.toDouble();
        final lng = (m?['longitude'] as num?)?.toDouble() ??
            (m?['workshop_longitude'] as num?)?.toDouble();
        final name = (m?['full_name'] as String?) ?? '';
        if (mounted) {
          setState(() {
            _providerLocations[mechId] = (lat: lat, lng: lng, name: name);
          });
        }
      } catch (_) {} finally {
        _fetchingProviderIds.remove('m_$mechId');
      }
    }

    final pickLat = (emg['pickup_latitude'] as num?)?.toDouble();
    final pickLng = (emg['pickup_longitude'] as num?)?.toDouble();
    final custId = (emg['user_id'] as String?) ?? '';
    final serviceType = (emg['service_type'] as String?) ?? 'mechanic';

    if (isProviderSide &&
        !_startedEmergencyTracking.contains(id) &&
        (status == 'accepted' || status == 'in_progress') &&
        (step == 'on_the_way' || step == 'accepted') &&
        pickLat != null &&
        pickLng != null &&
        custId.isNotEmpty) {
      _startedEmergencyTracking.add(id);
      _tracker.startTrackingEmergencyArrival(
        requestId: id,
        customerUserId: custId,
        serviceType: serviceType,
        pickupLat: pickLat,
        pickupLng: pickLng,
      );
    }
  }

  Future<void> _openInGoogleMaps({
    double? lat,
    double? lng,
    String? addressQuery,
  }) async {
    Uri uri;
    if (lat != null && lng != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      );
    } else {
      final q = Uri.encodeComponent((addressQuery ?? 'Amman Jordan').trim());
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showTopToast(String title, String msg, {bool isError = false}) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isError ? const Color(0xFFDC2626) : AppColors.success,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        msg,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }

  Future<void> _confirmAndCancelItem(_ProgressBannerItem item) async {
    final id = item.data['id'] as String;
    if (_cancellingIds.contains(id)) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          item.isWorkshop
              ? _loc.tr('إلغاء حجز الورشة', 'Cancel Workshop Booking')
              : _loc.tr('إلغاء طلب الطوارئ', 'Cancel Emergency Request'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          item.isWorkshop
              ? _loc.tr(
                  'هل أنت متأكد من إلغاء هذا الحجز؟ سيتم إشعار الطرف الآخر فوراً.',
                  'Are you sure you want to cancel this booking?',
                )
              : _loc.tr(
                  'هل أنت متأكد من إلغاء طلب الطوارئ؟ سيتم إيقاف التتبع وإشعار الطرف الآخر.',
                  'Are you sure you want to cancel this emergency request?',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_loc.tr('تراجع', 'Back')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_loc.tr('نعم، إلغاء الطلب', 'Yes, Cancel')),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _cancellingIds.add(id));
    try {
      final table =
          item.isWorkshop ? 'workshop_appointments' : 'mechanic_requests';
      await _db.from(table).update({
        'status': 'cancelled',
        'progress_step': 'cancelled',
      }).eq('id', id);

      _tracker.stop();

      final otherUserId = item.isWorkshop
          ? (item.isProviderSide
              ? item.data['user_id'] as String?
              : item.data['workshop_id'] as String?)
          : (item.isProviderSide
              ? item.data['user_id'] as String?
              : item.data['mechanic_id'] as String?);

      if (otherUserId != null && otherUserId.isNotEmpty) {
        await _notifs.sendNotification(
          targetUserId: otherUserId,
          title: item.isWorkshop ? 'تم إلغاء حجز الورشة' : 'تم إلغاء طلب الطوارئ',
          body: item.isProviderSide
              ? 'قام مقدم الخدمة بإلغاء الطلب.'
              : 'قام العميل بإلغاء الطلب قبل إتمامه.',
          type: 'order_cancelled',
          referenceId: id,
        );
      }

      _showTopToast(
        _loc.tr('تم الإلغاء بنجاح', 'Cancelled'),
        item.isWorkshop
            ? _loc.tr('تم إلغاء حجز الورشة.', 'Workshop booking cancelled.')
            : _loc.tr('تم إلغاء طلب الطوارئ.', 'Emergency request cancelled.'),
      );
    } catch (e) {
      _showTopToast(_loc.tr('تعذر الإلغاء', 'Cancel Failed'), '$e',
          isError: true);
    } finally {
      if (mounted) {
        setState(() => _cancellingIds.remove(id));
      }
    }
  }

  String _formatDistanceEta(double km) {
    final etaMins = (km * 2.2).round().clamp(1, 90);
    if (km < 1.0) {
      final meters = (km * 1000).round();
      return _loc.tr('يبعد $meters م · ~$etaMins د', '${meters}m · ~${etaMins}m');
    }
    return _loc.tr(
      'يبعد ${km.toStringAsFixed(1)} كم · ~$etaMins د',
      '${km.toStringAsFixed(1)} km · ~${etaMins}m',
    );
  }

  double _workshopProgressValue(String step, {double? gpsRatio}) {
    if (step == 'on_the_way' && gpsRatio != null) {
      return (0.15 + (gpsRatio.clamp(0.0, 1.0) * 0.27)).clamp(0.15, 0.42);
    }
    return switch (step) {
      'pending' => 0.12,
      'on_the_way' => 0.25,
      'arrived_at_workshop' => 0.45,
      'diagnosis' => 0.60,
      'repairing' => 0.75,
      'testing' => 0.88,
      'awaiting_payment' => 0.95,
      'completed' => 1.0,
      _ => 0.15,
    };
  }

  String _workshopStepLabel(String step, {bool isProviderSide = false}) {
    return switch (step) {
      'on_the_way' => isProviderSide
          ? _loc.tr('العميل في طريقه إلى الورشة (GPS)', 'Customer heading to workshop')
          : _loc.tr('في الطريق إلى الورشة (GPS)', 'On the way to workshop'),
      'arrived_at_workshop' =>
        _loc.tr('تم الوصول للورشة ✓', 'Arrived at workshop ✓'),
      'diagnosis' => _loc.tr('فحص السيارة وتشخيص العطل', 'Diagnosing vehicle'),
      'repairing' => _loc.tr('جاري الإصلاح في الورشة', 'Repairing vehicle'),
      'testing' => _loc.tr('الفحص والتجربة النهائية', 'Final testing'),
      'awaiting_payment' => _loc.tr(
          'السيارة جاهزة — بانتظار دفع الفاتورة',
          'Car ready — awaiting payment',
        ),
      'completed' => _loc.tr('مكتمل وتم التسليم ✓', 'Completed ✓'),
      _ => isProviderSide
          ? _loc.tr('حجز جديد بانتظار تأكيدك', 'New booking awaiting confirmation')
          : _loc.tr('بانتظار تأكيد الورشة', 'Awaiting workshop confirmation'),
    };
  }

  double _emergencyProgressValue(
    String status,
    String step, {
    double? gpsRatio,
  }) {
    if (step == 'completed' || status == 'completed') return 1.0;
    if (step == 'arrived_at_pickup') return 0.90;
    if ((step == 'on_the_way' || status == 'accepted' || status == 'in_progress') &&
        gpsRatio != null) {
      return (0.22 + (gpsRatio.clamp(0.0, 1.0) * 0.64)).clamp(0.22, 0.86);
    }
    if (step == 'on_the_way' || status == 'accepted' || status == 'in_progress') {
      return 0.45;
    }
    return 0.16;
  }

  String _emergencyStepLabel(
    String status,
    String step,
    String serviceType, {
    bool isProviderSide = false,
  }) {
    final isWinch = serviceType == 'winch';
    if (step == 'completed' || status == 'completed') {
      return _loc.tr('تم إنهاء المساعدة الطارئة ✓', 'Emergency completed ✓');
    }
    if (step == 'arrived_at_pickup') {
      return isWinch
          ? _loc.tr('وصل الونش إلى الموقع ✓', 'Tow truck arrived ✓')
          : _loc.tr('وصل الميكانيكي إلى الموقع ✓', 'Mechanic arrived ✓');
    }
    if (step == 'on_the_way' || status == 'accepted' || status == 'in_progress') {
      if (isProviderSide) {
        return isWinch
            ? _loc.tr('أنت في طريقك لموقع العميل (ونش)', 'Heading to customer (Winch)')
            : _loc.tr('أنت في طريقك لموقع العميل (طوارئ)', 'Heading to customer (Emergency)');
      }
      return isWinch
          ? _loc.tr('ونش الطوارئ في طريقه إلى موقعك', 'Tow truck is on the way')
          : _loc.tr('الميكانيكي في طريقه إلى موقعك', 'Mechanic is on the way');
    }
    return isWinch
        ? _loc.tr('جاري البحث عن أقرب ونش طوارئ...', 'Finding nearest tow truck...')
        : _loc.tr('جاري البحث عن أقرب ميكانيكي طوارئ...', 'Finding nearest mechanic...');
  }

  /// يختفي تلقائياً فور وصول الطلب لـ 100% (completed) أو إلغائه
  bool _isWorkshopActive(Map<String, dynamic> a) {
    final status = (a['status'] as String?) ?? 'pending';
    final step = (a['progress_step'] as String?) ?? 'pending';
    if (status == 'completed' ||
        step == 'completed' ||
        status == 'cancelled' ||
        status == 'rejected') {
      return false;
    }
    return status == 'pending' ||
        status == 'accepted' ||
        status == 'reschedule_proposed';
  }

  /// يختفي تلقائياً فور وصول الطلب لـ 100% (completed) أو إلغائه
  bool _isEmergencyActive(Map<String, dynamic> e) {
    final status = (e['status'] as String?) ?? 'pending';
    final step = (e['progress_step'] as String?) ?? 'pending';
    if (status == 'completed' ||
        step == 'completed' ||
        status == 'cancelled' ||
        status == 'rejected') {
      return false;
    }
    return true;
  }

  List<_ProgressBannerItem> _collectActiveItems() {
    final map = <String, _ProgressBannerItem>{};

    void addItem(
      Map<String, dynamic> row, {
      required bool isWorkshop,
      required bool isProviderSide,
    }) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) return;
      final key = '${isWorkshop ? 'w' : 'e'}_$id';
      final dt = DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now();
      map[key] = _ProgressBannerItem(
        keyId: key,
        isWorkshop: isWorkshop,
        isProviderSide: isProviderSide,
        data: row,
        createdAt: dt,
      );
    }

    for (final a in _custAppts) {
      if (_isWorkshopActive(a)) {
        addItem(a, isWorkshop: true, isProviderSide: false);
      }
    }
    for (final e in _custEmgs) {
      if (_isEmergencyActive(e)) {
        addItem(e, isWorkshop: false, isProviderSide: false);
      }
    }
    for (final a in _provAppts) {
      if (_isWorkshopActive(a)) {
        addItem(a, isWorkshop: true, isProviderSide: true);
      }
    }
    for (final e in _provEmgs) {
      if (_isEmergencyActive(e)) {
        addItem(e, isWorkshop: false, isProviderSide: true);
      }
    }

    final list = map.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final viewer = widget.viewerProfile;
    if (viewer == null) return const SizedBox.shrink();

    return ValueListenableBuilder<String>(
      valueListenable: _loc.langCode,
      builder: (_, __, ___) {
        final items = _collectActiveItems();
        if (items.isEmpty) return const SizedBox.shrink();

        final safePage = _currentPage.clamp(0, items.length - 1);

        if (items.length == 1) {
          return _buildItemCard(items.first, viewer);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.radar, color: AppColors.orange, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    _loc.tr(
                      'الطلبات النشطة (${items.length})',
                      'Active Requests (${items.length})',
                    ),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${safePage + 1} / ${items.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: safePage > 0
                        ? () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                            )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color:
                            safePage > 0 ? AppColors.navy : Colors.grey.shade400,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: safePage < items.length - 1
                        ? () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                            )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chevron_left,
                        size: 20,
                        color: safePage < items.length - 1
                            ? AppColors.navy
                            : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 215,
              child: PageView.builder(
                controller: _pageController,
                itemCount: items.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (_, idx) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child:
                        _buildItemCard(items[idx], viewer, inCarousel: true),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                items.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  width: i == safePage ? 18 : 6,
                  decoration: BoxDecoration(
                    color:
                        i == safePage ? AppColors.orange : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItemCard(
    _ProgressBannerItem item,
    CustomerProfile viewer, {
    bool inCarousel = false,
  }) {
    if (item.isWorkshop) {
      return _buildWorkshopCard(item, viewer, inCarousel: inCarousel);
    }
    return _buildEmergencyCard(item, viewer, inCarousel: inCarousel);
  }

  Widget _buildWorkshopCard(
    _ProgressBannerItem item,
    CustomerProfile viewer, {
    bool inCarousel = false,
  }) {
    final a = item.data;
    final id = a['id'] as String;
    final status = (a['status'] as String?) ?? 'pending';
    final step = (a['progress_step'] as String?) ?? 'pending';
    final amount = (a['total_amount'] as num?)?.toDouble() ?? 0.0;
    final payStatus = (a['payment_status'] as String?) ?? 'unpaid';

    _ensureWorkshopGps(a, isProviderSide: item.isProviderSide);
    final wLoc = _workshopLocations[a['workshop_id']];

    final canCancel = status != 'completed' &&
        status != 'cancelled' &&
        payStatus != 'paid';

    final canPayWorkshop = !item.isProviderSide &&
        payStatus != 'paid' &&
        amount > 0;

    return ListenableBuilder(
      listenable: Listenable.merge([
        _tracker.workshopDistanceKm,
        _tracker.workshopGpsProgress,
      ]),
      builder: (_, __) {
        double? distKm;
        double? gpsRatio;

        if (step == 'on_the_way') {
          if (!item.isProviderSide) {
            distKm = _tracker.workshopDistanceKm.value;
            if (distKm != null) {
              gpsRatio = _tracker.workshopGpsProgress.value;
            }
          } else {
            final cLat = (a['customer_latitude'] as num?)?.toDouble();
            final cLng = (a['customer_longitude'] as num?)?.toDouble();
            if (cLat != null &&
                cLng != null &&
                wLoc?.lat != null &&
                wLoc?.lng != null) {
              distKm = LiveProgressTracker.distanceKmBetween(
                cLat,
                cLng,
                wLoc!.lat!,
                wLoc.lng!,
              );
              gpsRatio = _tracker.computeGpsProgress('w_prov_$id', distKm);
            }
          }
        }

        final progress = _workshopProgressValue(step, gpsRatio: gpsRatio);
        if (progress >= 1.0) return const SizedBox.shrink();

        final baseLabel = status == 'reschedule_proposed'
            ? _loc.tr('اقترحت الورشة موعداً بديلاً', 'Workshop proposed new time')
            : _workshopStepLabel(step, isProviderSide: item.isProviderSide);
        final fullStatus = (step == 'on_the_way' && distKm != null)
            ? '$baseLabel · ${_formatDistanceEta(distKm)}'
            : baseLabel;

        DynamicIslandService.instance.syncProgress(
          keyId: 'appt_$id',
          title: _loc.tr('صيانة الورشة', 'Workshop Service'),
          statusText: fullStatus,
          progress: progress,
          etaOrDistance: distKm != null
              ? '${distKm.toStringAsFixed(1)} km'
              : '${a['appointment_time'] ?? ""}',
        );

        return _progressCard(
          inCarousel: inCarousel,
          headerIcon: Icons.build_circle,
          thumbIcon: step == 'on_the_way' ? Icons.directions_car : Icons.build,
          title: item.isProviderSide
              ? _loc.tr(
                  'حجز عميل بالورشة (${a['appointment_date'] ?? ''})',
                  'Workshop Booking (${a['appointment_date'] ?? ''})',
                )
              : _loc.tr(
                  'حالة موعد الورشة (${a['appointment_date'] ?? ''})',
                  'Workshop Appointment (${a['appointment_date'] ?? ''})',
                ),
          statusText: fullStatus,
          progress: progress,
          paymentStatus: payStatus,
          isCancelling: _cancellingIds.contains(id),
          payLabel: canPayWorkshop
              ? _loc.tr(
                  'دفع الفاتورة (${amount.toStringAsFixed(2)} د.أ)',
                  'Pay Invoice (${amount.toStringAsFixed(2)} JOD)',
                )
              : null,
          onPayInvoice: canPayWorkshop
              ? () => Navigator.push(
                    context,
                    animatedRoute(
                      WorkshopCheckoutScreen(
                        appointment: DbWorkshopAppointment.fromMap(a),
                        customerProfile: viewer,
                        onPaymentCompleted: () {
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  )
              : null,
          actionLabel: (!item.isProviderSide && step == 'on_the_way')
              ? _loc.tr('تأكيد وصولي', 'I Arrived')
              : null,
          onAction: (!item.isProviderSide &&
                  step == 'on_the_way' &&
                  a['workshop_id'] != null)
              ? () => _tracker.markWorkshopArrived(
                    appointmentId: id,
                    workshopUserId: a['workshop_id'],
                  )
              : null,
          onCancel: canCancel ? () => _confirmAndCancelItem(item) : null,
          onOpenMaps: () => _openInGoogleMaps(
            lat: wLoc?.lat,
            lng: wLoc?.lng,
            addressQuery: wLoc?.address,
          ),
        );
      },
    );
  }

  Widget _buildEmergencyCard(
    _ProgressBannerItem item,
    CustomerProfile viewer, {
    bool inCarousel = false,
  }) {
    final e = item.data;
    final id = e['id'] as String;
    final status = (e['status'] as String?) ?? 'pending';
    final step = (e['progress_step'] as String?) ?? 'pending';
    final serviceType = (e['service_type'] as String?) ?? 'mechanic';
    final isWinch = serviceType == 'winch';
    final pickLat = (e['pickup_latitude'] as num?)?.toDouble();
    final pickLng = (e['pickup_longitude'] as num?)?.toDouble();
    final amount = (e['total_amount'] as num?)?.toDouble() ?? 0.0;
    final payStatus = (e['payment_status'] as String?) ?? 'unpaid';
    final mechId = e['mechanic_id'] as String?;

    _ensureEmergencyGps(e, isProviderSide: item.isProviderSide);

    final canCancel = status != 'completed' &&
        status != 'cancelled' &&
        payStatus != 'paid';

    final canPayEmergency = !item.isProviderSide &&
        payStatus != 'paid' &&
        amount > 0 &&
        (mechId != null && mechId.isNotEmpty);

    return ListenableBuilder(
      listenable: Listenable.merge([
        _tracker.emergencyDistanceKm,
        _tracker.emergencyGpsProgress,
      ]),
      builder: (_, __) {
        double? distKm;
        double? gpsRatio;

        final isEnRoute = step == 'on_the_way' ||
            status == 'accepted' ||
            status == 'in_progress';

        if (isEnRoute && step != 'arrived_at_pickup' && status != 'completed') {
          if (item.isProviderSide && _tracker.emergencyDistanceKm.value != null) {
            distKm = _tracker.emergencyDistanceKm.value;
            gpsRatio = _tracker.emergencyGpsProgress.value;
          } else if (pickLat != null && pickLng != null) {
            final liveLat = (e['latitude'] as num?)?.toDouble() ??
                (mechId != null ? _providerLocations[mechId]?.lat : null);
            final liveLng = (e['longitude'] as num?)?.toDouble() ??
                (mechId != null ? _providerLocations[mechId]?.lng : null);

            if (liveLat != null && liveLng != null) {
              distKm = LiveProgressTracker.distanceKmBetween(
                liveLat,
                liveLng,
                pickLat,
                pickLng,
              );
              gpsRatio = _tracker.computeGpsProgress('emg_$id', distKm);
            }
          }
        }

        final progress =
            _emergencyProgressValue(status, step, gpsRatio: gpsRatio);
        if (progress >= 1.0) return const SizedBox.shrink();

        final baseLabel = _emergencyStepLabel(
          status,
          step,
          serviceType,
          isProviderSide: item.isProviderSide,
        );
        final fullStatus = (isEnRoute &&
                step != 'arrived_at_pickup' &&
                status != 'completed' &&
                distKm != null)
            ? '$baseLabel · ${_formatDistanceEta(distKm)}'
            : baseLabel;

        DynamicIslandService.instance.syncProgress(
          keyId: 'emg_$id',
          title: isWinch
              ? _loc.tr('ونش طوارئ غيارك', 'Ghiyarak Tow Truck')
              : _loc.tr('ميكانيكي طوارئ غيارك', 'Ghiyarak Mechanic'),
          statusText: fullStatus,
          progress: progress,
          etaOrDistance: distKm != null
              ? '${distKm.toStringAsFixed(1)} km'
              : ((e['estimated_time'] as String?) ?? ''),
        );

        return _progressCard(
          inCarousel: inCarousel,
          headerIcon: isWinch ? Icons.local_shipping : Icons.car_crash,
          thumbIcon: isWinch ? Icons.local_shipping : Icons.build,
          title: item.isProviderSide
              ? _loc.tr(
                  'مهمة طوارئ (${e['car_details'] ?? e['description'] ?? ''})',
                  'Emergency Task (${e['car_details'] ?? e['description'] ?? ''})',
                )
              : _loc.tr(
                  '${isWinch ? 'طلب ونش طوارئ' : 'طلب ميكانيكي طوارئ'} (${e['description'] ?? ''})',
                  '${isWinch ? 'Tow Request' : 'Mechanic Request'} (${e['description'] ?? ''})',
                ),
          statusText: fullStatus,
          progress: progress,
          paymentStatus: payStatus,
          isCancelling: _cancellingIds.contains(id),
          payLabel: canPayEmergency
              ? _loc.tr(
                  'دفع الفاتورة (${amount.toStringAsFixed(2)} د.أ)',
                  'Pay Invoice (${amount.toStringAsFixed(2)} JOD)',
                )
              : null,
          onPayInvoice: canPayEmergency
              ? () => Navigator.push(
                    context,
                    animatedRoute(
                      EmergencyCheckoutScreen(
                        request: DbMechanicRequest.fromMap(e),
                        customerProfile: viewer,
                        onPaymentCompleted: () {
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  )
              : null,
          actionLabel: (item.isProviderSide &&
                  isEnRoute &&
                  step != 'arrived_at_pickup' &&
                  status != 'completed')
              ? _loc.tr('تأكيد وصولي للموقع', 'Confirm Arrival')
              : null,
          onAction: (item.isProviderSide &&
                  isEnRoute &&
                  step != 'arrived_at_pickup' &&
                  status != 'completed')
              ? () => _tracker.markEmergencyArrived(
                    requestId: id,
                    customerUserId: (e['user_id'] as String?) ?? '',
                    serviceType: serviceType,
                  )
              : null,
          onCancel: canCancel ? () => _confirmAndCancelItem(item) : null,
          onOpenMaps: () => _openInGoogleMaps(
            lat: pickLat,
            lng: pickLng,
            addressQuery: e['dropoff_address'] as String?,
          ),
        );
      },
    );
  }

  Widget _progressCard({
    bool inCarousel = false,
    required IconData headerIcon,
    required IconData thumbIcon,
    required String title,
    required String statusText,
    required double progress,
    required String paymentStatus,
    bool isCancelling = false,
    String? payLabel,
    VoidCallback? onPayInvoice,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onCancel,
    VoidCallback? onOpenMaps,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: inCarousel ? 0 : 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(headerIcon, color: AppColors.orange, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              if (paymentStatus == 'paid')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _loc.tr('تم الدفع ✓', 'Paid ✓'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOutCubic,
            builder: (_, val, __) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  const double thumbSize = 26.0;
                  final fillWidth = trackWidth * val;
                  final thumbStart = (trackWidth - thumbSize) * val;

                  return SizedBox(
                    height: thumbSize + 4,
                    child: Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [
                        Container(
                          height: 7,
                          width: trackWidth,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        PositionedDirectional(
                          start: 0,
                          child: Container(
                            height: 7,
                            width: fillWidth,
                            decoration: BoxDecoration(
                              color: AppColors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          start: thumbStart,
                          child: Container(
                            width: thumbSize,
                            height: thumbSize,
                            decoration: BoxDecoration(
                              color: AppColors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.orange.withValues(alpha: 0.45),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Icon(
                              thumbIcon,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (onPayInvoice != null && payLabel != null)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onPayInvoice,
                  icon: const Icon(Icons.receipt_long, size: 15),
                  label: Text(
                    payLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (onOpenMaps != null)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onOpenMaps,
                  icon: const Icon(Icons.map_outlined, size: 15),
                  label: Text(
                    _loc.tr('الخريطة', 'Map'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onAction,
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              if (onCancel != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.18),
                    foregroundColor: const Color(0xFFFFB4B4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: isCancelling ? null : onCancel,
                  icon: isCancelling
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cancel_outlined, size: 15),
                  label: Text(
                    _loc.tr('إلغاء الطلب', 'Cancel'),
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}