import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:isar/isar.dart';
import '../models/database_models.dart';
import 'places_cache_service.dart';

/// Wraps a detected store. Either a shop already saved in Isar (known),
/// or a fresh suggestion from the Places API cache (new/unsaved).
class DetectedShop {
  /// Non-null when the match came from a saved [UserShop] geofence.
  final UserShop? savedShop;

  /// Non-null when the match came from the Places API cache.
  final CachedPlace? apiPlace;

  const DetectedShop.known(UserShop shop)
      : savedShop = shop,
        apiPlace = null;

  const DetectedShop.fromApi(CachedPlace place)
      : savedShop = null,
        apiPlace = place;

  /// True when this store is NOT yet in the user's Isar shop list.
  bool get isNew => savedShop == null;

  /// Display name regardless of source.
  String get name => savedShop?.name ?? apiPlace?.name ?? '';

  double? get lat => savedShop?.lat ?? apiPlace?.lat;
  double? get lng => savedShop?.lng ?? apiPlace?.lng;

  @override
  bool operator ==(Object other) =>
      other is DetectedShop &&
      savedShop?.id == other.savedShop?.id &&
      apiPlace?.placeId == other.apiPlace?.placeId;

  @override
  int get hashCode => Object.hash(savedShop?.id, apiPlace?.placeId);
}

/// Tracks the user's position and emits a [DetectedShop] whenever they
/// enter or leave a known geofence, falling back to the Places API cache
/// when no saved shop matches.
class LocationRoutingService {
  final Isar isar;
  final _placesCache = PlacesCacheService();

  StreamSubscription<Position>? _positionSub;
  final _shopController = StreamController<DetectedShop?>.broadcast();

  DetectedShop? _lastEmitted;

  LocationRoutingService(this.isar);

  Stream<DetectedShop?> get currentShopStream => _shopController.stream;

  Future<void> startTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15, // emit every 15 m — good balance of battery vs. accuracy
    );

    // Baseline fix before the stream starts
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _evaluate(pos);
    } catch (e) {
      debugPrint('[LocationRoutingService] initial fix error: $e');
    }

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) => _evaluate(pos));
  }

  // ── Core evaluation ──────────────────────────────────────────────────────────

  Future<void> _evaluate(Position pos) async {
    final result = await _resolve(pos);

    // Only emit when something has actually changed
    if (result != _lastEmitted) {
      _lastEmitted = result;
      _shopController.add(result);
    }
  }

  /// Phase 1 → known Isar geofences.
  /// Phase 2 → Places API cache fallback (when outside all known geofences).
  Future<DetectedShop?> _resolve(Position pos) async {
    // --- Phase 1: Check saved shops ----------------------------------------
    final shops = await isar.userShops.where().findAll();
    for (final shop in shops) {
      if (shop.lat == null || shop.lng == null) continue;
      final dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        shop.lat!, shop.lng!,
      );
      if (dist <= shop.radius) {
        return DetectedShop.known(shop);
      }
    }

    // --- Phase 2: Places API cache (offline-first) -------------------------
    try {
      final places = await _placesCache.getNearbyStores(pos.latitude, pos.longitude);
      if (places.isNotEmpty) {
        // Pick the closest result to the user's exact position
        places.sort((a, b) {
          final da = Geolocator.distanceBetween(pos.latitude, pos.longitude, a.lat, a.lng);
          final db = Geolocator.distanceBetween(pos.latitude, pos.longitude, b.lat, b.lng);
          return da.compareTo(db);
        });
        return DetectedShop.fromApi(places.first);
      }
    } catch (e) {
      debugPrint('[LocationRoutingService] Places fallback error: $e');
    }

    return null; // Outside all known geofences and Places returned nothing
  }

  void stopTracking() {
    _positionSub?.cancel();
    _shopController.close();
  }
}
