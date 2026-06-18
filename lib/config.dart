/// App-wide configuration constants.
/// Replace the Places API key below with your own from Google Cloud Console.
/// Enable "Places API" in your project: https://console.cloud.google.com/apis/library/places-backend.googleapis.com
class AppConfig {
  /// Your Google Places API key. The app functions without it (falls back to
  /// the manual shop picker), but providing one enables automatic store detection.
  static const String googlePlacesApiKey = 'YOUR_GOOGLE_PLACES_API_KEY';
  
  /// Radius (in metres) used when searching for nearby stores via the Places API.
  static const int placesSearchRadius = 200;
  
  /// How many days a Places API result is considered fresh before re-fetching.
  static const int placesCacheTtlDays = 7;
  
  /// Geographic cell size for cache bucketing (in degrees).
  /// 0.01° ≈ 1.1 km — coarse enough to share cache across a shopping complex.
  static const double placesCellSize = 0.01;
}
