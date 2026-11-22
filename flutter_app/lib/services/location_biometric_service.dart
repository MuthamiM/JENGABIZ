import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KenyanSupplyHub {
  final String name;
  final double latitude;
  final double longitude;
  final String region;

  const KenyanSupplyHub({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.region,
  });
}

class LocationBiometricService {
  static final LocationBiometricService instance = LocationBiometricService._();
  LocationBiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  // Kenyan regional supply and distribution centers
  static const List<KenyanSupplyHub> supplyHubs = [
    KenyanSupplyHub(
      name: 'Nairobi Central CBD Depot',
      latitude: -1.286389,
      longitude: 36.817223,
      region: 'Nairobi County',
    ),
    KenyanSupplyHub(
      name: 'Eastleigh Wholesale Hub',
      latitude: -1.2778,
      longitude: 36.8522,
      region: 'Nairobi East',
    ),
    KenyanSupplyHub(
      name: 'Industrial Area Logistics Point',
      latitude: -1.3120,
      longitude: 36.8450,
      region: 'Nairobi South',
    ),
    KenyanSupplyHub(
      name: 'Mombasa Port Distribution Hub',
      latitude: -4.0435,
      longitude: 39.6682,
      region: 'Coast Region',
    ),
    KenyanSupplyHub(
      name: 'Kisumu Western Regional Hub',
      latitude: -0.1022,
      longitude: 34.7617,
      region: 'Western Region',
    ),
    KenyanSupplyHub(
      name: 'Nakuru Rift Valley Depot',
      latitude: -0.3031,
      longitude: 36.0800,
      region: 'Rift Valley',
    ),
    KenyanSupplyHub(
      name: 'Eldoret North Rift Hub',
      latitude: 0.5143,
      longitude: 35.2698,
      region: 'North Rift',
    ),
  ];

  // -------------------------------------------------------------
  // BIOMETRICS (FINGERPRINT)
  // -------------------------------------------------------------

  Future<bool> canUseBiometrics() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> authenticateBiometric({
    String reason = 'Scan fingerprint or Face ID to access your shop ledger',
  }) async {
    try {
      final available = await canUseBiometrics();
      if (!available) return false;

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String> getBiometricTypeLabel() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face) && types.contains(BiometricType.fingerprint)) {
        return 'Fingerprint & Face ID';
      } else if (types.contains(BiometricType.face)) {
        return 'Face ID';
      } else if (types.contains(BiometricType.fingerprint)) {
        return 'Fingerprint';
      }
      return 'Fingerprint & Face ID';
    } catch (_) {
      return 'Fingerprint & Face ID';
    }
  }

  Future<bool> isFingerprintEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometric_enabled') ?? false;
  }

  Future<void> setFingerprintEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', enabled);
  }

  // -------------------------------------------------------------
  // LOCATION (PRECISE GPS)
  // -------------------------------------------------------------

  Future<Position?> getPreciseLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Return null or let user know service is off
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  KenyanSupplyHub findNearestHub(double lat, double lng) {
    KenyanSupplyHub closest = supplyHubs.first;
    double minDistance = double.infinity;

    for (final hub in supplyHubs) {
      final dist = Geolocator.distanceBetween(
        lat,
        lng,
        hub.latitude,
        hub.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        closest = hub;
      }
    }
    return closest;
  }

  double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    final meters = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    return meters / 1000.0;
  }
}
