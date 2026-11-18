import 'dart:ui';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationResult {
  final LatLng coordinates;
  final String address;
  final double distanceKm;

  LocationResult({
    required this.coordinates,
    required this.address,
    required this.distanceKm,
  });
}

class LocationService {
  static const LatLng nearestHub = LatLng(31.9539, 35.9106);

  Future<LocationResult> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _fallback('عمّان - موقع افتراضي');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return _fallback('عمّان - موقع افتراضي');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return _fallback('يرجى تفعيل صلاحية الموقع من الإعدادات');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      final address = await getAddressFromLatLng(latLng);
      final dist = calculateDistanceKm(latLng, nearestHub);

      return LocationResult(
          coordinates: latLng, address: address, distanceKm: dist);
    } catch (_) {
      return _fallback('عمّان - شارع مكة، بالقرب من سيتي مول');
    }
  }

  Future<String> getAddressFromLatLng(LatLng coords) async {
    try {
      final geocoding = Geocoding(locale: const Locale('ar'));
      final placemarks = await geocoding.placemarkFromCoordinates(
        coords.latitude,
        coords.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.locality, p.subLocality, p.street]
            .where((e) => e != null && e.trim().isNotEmpty)
            .toList();
        if (parts.isNotEmpty) return parts.join(' - ');
      }
    } catch (_) {}
    return '${coords.latitude.toStringAsFixed(4)}, ${coords.longitude.toStringAsFixed(4)}';
  }

  double calculateDistanceKm(LatLng from, LatLng to) {
    final meters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    return (meters / 1000).clamp(1.0, 100.0);
  }

  LocationResult _fallback(String msg) {
    const defaultLatLng = LatLng(31.9720, 35.8450);
    return LocationResult(
      coordinates: defaultLatLng,
      address: msg,
      distanceKm: calculateDistanceKm(defaultLatLng, nearestHub),
    );
  }
}
