import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config.dart';

/// A store found via the Google Places API.
class CachedPlace {
  final String name;
  final double lat;
  final double lng;
  final String placeId;

  const CachedPlace({
    required this.name,
    required this.lat,
    required this.lng,
    required this.placeId,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'placeId': placeId,
  };

  factory CachedPlace.fromJson(Map<String, dynamic> j) => CachedPlace(
    name: j['name'] as String,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    placeId: j['placeId'] as String,
  );
}

class _CacheEntry {
  final List<CachedPlace> places;
  final DateTime cachedAt;

  _CacheEntry({required this.places, required this.cachedAt});

  bool get isFresh =>
      DateTime.now().difference(cachedAt).inDays < AppConfig.placesCacheTtlDays;

  Map<String, dynamic> toJson() => {
    'cachedAt': cachedAt.toIso8601String(),
    'places': places.map((p) => p.toJson()).toList(),
  };

  factory _CacheEntry.fromJson(Map<String, dynamic> j) => _CacheEntry(
    cachedAt: DateTime.parse(j['cachedAt'] as String),
    places: (j['places'] as List)
        .map((p) => CachedPlace.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}

/// Offline-first store detection via Google Places API with file-based JSON cache.
///
/// Strategy:
///   1. Round lat/lng to a cache cell (~1.1 km). Return fresh cached results instantly.
///   2. If cache is stale AND internet is available → fetch from Places API, update cache.
///   3. If no internet → serve stale cache (better than nothing).
///   4. If cache is empty AND no internet → return [] (caller shows manual picker).
class PlacesCacheService {
  static final PlacesCacheService _instance = PlacesCacheService._();
  PlacesCacheService._();
  factory PlacesCacheService() => _instance;

  final Map<String, _CacheEntry> _memCache = {};
  File? _file;
  bool _loaded = false;

  // ── Initialisation ──────────────────────────────────────────────────────────

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/places_cache.json');
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        data.forEach((key, value) {
          _memCache[key] = _CacheEntry.fromJson(value as Map<String, dynamic>);
        });
      }
    } catch (e) {
      debugPrint('[PlacesCache] load error: $e');
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final data = {
        for (final e in _memCache.entries) e.key: e.value.toJson(),
      };
      await _file?.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[PlacesCache] persist error: $e');
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Returns nearby store suggestions for the given coordinates.
  /// Tries the cache first, then the Places API if needed.
  Future<List<CachedPlace>> getNearbyStores(double lat, double lng) async {
    await _ensureLoaded();
    final key = _cellKey(lat, lng);
    final cached = _memCache[key];

    // 1. Fresh cache hit → return immediately
    if (cached != null && cached.isFresh) {
      debugPrint('[PlacesCache] cache hit for $key');
      return cached.places;
    }

    // 2. Try network
    if (AppConfig.googlePlacesApiKey != 'YOUR_GOOGLE_PLACES_API_KEY') {
      try {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity.first != ConnectivityResult.none) {
          final places = await _fetchFromApi(lat, lng);
          if (places.isNotEmpty) {
            _memCache[key] = _CacheEntry(places: places, cachedAt: DateTime.now());
            await _persist();
            debugPrint('[PlacesCache] API fetch OK, ${places.length} stores');
            return places;
          }
        }
      } catch (e) {
        debugPrint('[PlacesCache] API error: $e');
      }
    }

    // 3. Serve stale cache as a last resort
    if (cached != null) {
      debugPrint('[PlacesCache] serving stale cache for $key');
      return cached.places;
    }

    return [];
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Rounds coordinates to the configured cell size for cache bucketing.
  String _cellKey(double lat, double lng) {
    final rLat = (lat / AppConfig.placesCellSize).round() * AppConfig.placesCellSize;
    final rLng = (lng / AppConfig.placesCellSize).round() * AppConfig.placesCellSize;
    return '${rLat.toStringAsFixed(4)},${rLng.toStringAsFixed(4)}';
  }

  Future<List<CachedPlace>> _fetchFromApi(double lat, double lng) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$lat,$lng'
      '&radius=${AppConfig.placesSearchRadius}'
      '&type=supermarket'
      '&key=${AppConfig.googlePlacesApiKey}',
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return [];

    return (data['results'] as List).take(5).map((r) {
      final loc = r['geometry']['location'];
      return CachedPlace(
        name: r['name'] as String,
        lat: (loc['lat'] as num).toDouble(),
        lng: (loc['lng'] as num).toDouble(),
        placeId: r['place_id'] as String,
      );
    }).toList();
  }
}
