import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/env_config.dart';
import '../../models/db_models.dart';
import '../../models/subscription_plans.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animations.dart';

class EmergencyScreen extends StatefulWidget {
  final CustomerProfile profile;
  const EmergencyScreen({super.key, required this.profile});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final _db = Supabase.instance.client;
  final _locationService = LocationService();
  final _mapController = MapController();
  final _carCtrl = TextEditingController(text: 'تويوتا كامري 2022');

  late String _serviceType =
      EnvConfig.winchEnabled.value ? 'winch' : 'mechanic';
  String _selectedProblem = 'بطارية';
  bool _pickingDropoff = false;
  bool _loadingGps = false;
  bool _submitting = false;

  LatLng _pickupLatLng = const LatLng(31.9720, 35.8450);
  LatLng _dropoffLatLng = const LatLng(31.9539, 35.9106);
  String _pickupAddress = 'جاري تحديد موقعك...';
  String _dropoffAddress = 'أقرب مركز صيانة / ورشة';
  double _distanceKm = 6.0;
  double _kmRate = 1.5;

  final Map<String, double> _baseFees = const {
    'بطارية': 15.0,
    'إطار': 12.0,
    'محرك': 25.0,
    'وقود': 10.0,
    'حادث': 35.0,
  };

  @override
  void initState() {
    super.initState();
    _loadKmRate();
    _detectMyLocation();
  }

  @override
  void dispose() {
    _carCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKmRate() async {
    try {
      final row = await _db
          .from('system_settings')
          .select('value')
          .eq('key', 'winch_price_per_km')
          .maybeSingle();
      if (row != null && mounted) {
        setState(
            () => _kmRate = double.tryParse(row['value'] as String) ?? 1.5);
      }
    } catch (_) {}
  }

  Future<void> _detectMyLocation() async {
    setState(() => _loadingGps = true);
    final res = await _locationService.getCurrentLocation();
    if (!mounted) {
      return;
    }
    setState(() {
      _pickupLatLng = res.coordinates;
      _pickupAddress = res.address;
      _distanceKm =
          _locationService.calculateDistanceKm(_pickupLatLng, _dropoffLatLng);
      _loadingGps = false;
    });
    _mapController.move(_pickupLatLng, 13.5);
  }

  Future<void> _onMapTap(LatLng latLng) async {
    final addr = await _locationService.getAddressFromLatLng(latLng);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_pickingDropoff &&
          _serviceType == 'winch' &&
          EnvConfig.winchEnabled.value) {
        _dropoffLatLng = latLng;
        _dropoffAddress = addr;
      } else {
        _pickupLatLng = latLng;
        _pickupAddress = addr;
      }
      _distanceKm =
          _locationService.calculateDistanceKm(_pickupLatLng, _dropoffLatLng);
    });
  }

  Future<void> _submitOrder(double finalPrice, int etaMinutes) async {
    final useWinch = EnvConfig.winchEnabled.value && _serviceType == 'winch';
    setState(() => _submitting = true);
    try {
      await _db.from('mechanic_requests').insert({
        'user_id': widget.profile.id,
        'service_type': useWinch ? 'winch' : 'mechanic',
        'car_details': _carCtrl.text.trim(),
        'phone': widget.profile.phone,
        'description': _selectedProblem,
        'latitude': _pickupLatLng.latitude,
        'longitude': _pickupLatLng.longitude,
        'pickup_latitude': _pickupLatLng.latitude,
        'pickup_longitude': _pickupLatLng.longitude,
        'dropoff_latitude': useWinch ? _dropoffLatLng.latitude : null,
        'dropoff_longitude': useWinch ? _dropoffLatLng.longitude : null,
        'dropoff_address': useWinch ? _dropoffAddress : _pickupAddress,
        'total_amount': EnvConfig.paymentsEnabled.value ? finalPrice : 0.0,
        'estimated_time': '$etaMinutes دقيقة',
        'status': 'pending',
        'progress_step': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال طلب الطوارئ بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        EnvConfig.winchEnabled,
        EnvConfig.paymentsEnabled,
      ]),
      builder: (context, _) {
        final showWinch = EnvConfig.winchEnabled.value;
        final showPayments = EnvConfig.paymentsEnabled.value;

        if (!showWinch && _serviceType == 'winch') {
          _serviceType = 'mechanic';
          _pickingDropoff = false;
        }

        final isWinch = showWinch && _serviceType == 'winch';
        final base = _baseFees[_selectedProblem]!;
        final raw = base + (isWinch ? (_distanceKm * _kmRate) : 5.0);
        final isPro = AppSubscriptionCatalog.customerFeeRate(
                widget.profile.subscriptionPlan) ==
            0.0;
        final finalPrice =
            double.parse((isPro ? raw * 0.85 : raw).toStringAsFixed(2));
        final eta = (_distanceKm * 2.4).round().clamp(8, 45);

        return SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      showWinch ? 'طلب مساعدة طارئة' : 'طلب ميكانيكي طوارئ',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    // يظهر خيار ونش / ميكانيكي فقط عندما يكون الونش مفعلاً
                    if (showWinch) ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            _segTab('ونش', isWinch,
                                () => setState(() => _serviceType = 'winch')),
                            _segTab(
                              'ميكانيكي طوارئ',
                              !isWinch,
                              () => setState(() => _serviceType = 'mechanic'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (isWinch)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                    child:
                                        Text('تحديد نقطة الالتقاط (Pickup)')),
                                selected: !_pickingDropoff,
                                selectedColor: AppColors.navy,
                                labelStyle: TextStyle(
                                  color: !_pickingDropoff
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontSize: 11,
                                ),
                                onSelected: (_) =>
                                    setState(() => _pickingDropoff = false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(
                                    child: Text('تحديد الوجهة (Drop-off)')),
                                selected: _pickingDropoff,
                                selectedColor: AppColors.orange,
                                labelStyle: TextStyle(
                                  color: _pickingDropoff
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontSize: 11,
                                ),
                                onSelected: (_) =>
                                    setState(() => _pickingDropoff = true),
                              ),
                            ),
                          ],
                        ),
                      ),

                    SizedBox(
                      height: 195,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _pickupLatLng,
                                initialZoom: 13.5,
                                onTap: (_, latLng) => _onMapTap(latLng),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.autoparts.app',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _pickupLatLng,
                                      width: 72,
                                      height: 72,
                                      child: const PulsingPin(
                                          color: AppColors.orange),
                                    ),
                                    if (isWinch)
                                      Marker(
                                        point: _dropoffLatLng,
                                        width: 44,
                                        height: 44,
                                        child: const Icon(
                                          Icons.flag,
                                          color: AppColors.navy,
                                          size: 34,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              bottom: 10,
                              left: 10,
                              child: FloatingActionButton.small(
                                backgroundColor: AppColors.navy,
                                foregroundColor: Colors.white,
                                onPressed: _detectMyLocation,
                                child: _loadingGps
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.my_location),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _infoRow('موقعك الحالي', _pickupAddress),
                    if (isWinch) ...[
                      const SizedBox(height: 8),
                      _infoRow('الوجهة (Drop-off)', _dropoffAddress),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: _carCtrl,
                      decoration: InputDecoration(
                        labelText: 'تفاصيل السيارة',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('ما المشكلة؟',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _baseFees.keys.map((problem) {
                        final selected = _selectedProblem == problem;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedProblem = problem),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 9),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.orangeLight
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: selected
                                    ? AppColors.orange
                                    : AppColors.border,
                                width: selected ? 1.6 : 1,
                              ),
                            ),
                            child: Text(
                              problem,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.orange
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _infoRow('الوصول المتوقع', '$eta دقيقة'),
                    if (showPayments) ...[
                      const SizedBox(height: 8),
                      _infoRow('السعر التقديري',
                          '${finalPrice.toStringAsFixed(2)} د.أ'),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 26),
                child: BounceTap(
                  onTap:
                      _submitting ? () {} : () => _submitOrder(finalPrice, eta),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _submitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'تأكيد الطلب',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _segTab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
