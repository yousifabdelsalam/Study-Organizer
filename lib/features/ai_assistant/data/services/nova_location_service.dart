// nova_location_service.dart
// Geolocator DEACTIVATED — all methods return safe defaults.
// To re-enable, uncomment the geolocator import and restore method bodies.

// import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NovaLocationService {
  static const _prefHomeLat = 'nova_home_lat';
  static const _prefHomeLng = 'nova_home_lng';

  // ── Save current position as home (disabled) ─────────────────────────────
  static Future<bool> saveHomeLocation() async {
    return false; // Geolocator disabled
  }

  // ── Check if user is at home (disabled) ───────────────────────────────────
  static Future<bool> isAtHome() async {
    return false; // Geolocator disabled — always returns false
  }

  static bool hasHomeSet = false;
  static Future<void> checkHomeSet() async {
    final prefs = await SharedPreferences.getInstance();
    hasHomeSet = prefs.getDouble(_prefHomeLat) != null;
  }

  static Future<void> clearHome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefHomeLat);
    await prefs.remove(_prefHomeLng);
    hasHomeSet = false;
  }
}
