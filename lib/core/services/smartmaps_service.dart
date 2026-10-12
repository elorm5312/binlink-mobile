import 'package:dio/dio.dart';
import '../config/env.dart';
import 'package:binlink_mobile/core/utils/json_num.dart';

/// SmartMaps location intelligence layer.
///
/// Provides:
///   - Address autocomplete  (POST autocomplete.smartmaps.cloud, Bearer token)
///   - Forward geocoding     (POST yellowmap.de geocode API)
///   - Reverse geocoding     (POST yellowmap.de geocode API, REVERSE_GEOCODE type)
///
/// All methods return null / empty list on failure so callers can cascade
/// to TomTom → Nominatim fallbacks.
class SmartMapsResult {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String fullText;
  final double? lat;
  final double? lng;

  const SmartMapsResult({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
    this.lat,
    this.lng,
  });
}

class SmartMapsService {
  SmartMapsService._();

  static String get _apiKey => Env.smartmapsApiKey;
  static bool get isAvailable => _apiKey.isNotEmpty;

  static final _autocomplete = Dio(BaseOptions(
    baseUrl: 'https://autocomplete.smartmaps.cloud',
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  static final _geocode = Dio(BaseOptions(
    baseUrl: 'https://www.yellowmap.de',
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  // ── Autocomplete ───────────────────────────────────────────────────────────

  static Future<List<SmartMapsResult>> autocomplete(
    String query, {
    double lat = 5.6037,
    double lng = -0.1870,
    String countryCode = 'GH',
  }) async {
    if (!isAvailable || query.trim().length < 2) return [];
    try {
      final resp = await _autocomplete.post(
        '/api/v5/Autocomplete',
        options: Options(headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        }),
        data: {
          'query': query,
          'top': 5,
          'isoCountries': [countryCode],
          'isoLanguages': ['en'],
          'center': {'latitude': lat, 'longitude': lng},
          'boostOptions': {'proximityBoost': true},
        },
      );

      final features = _extractFeatures(resp.data);
      return features.map((f) {
        final props = f['properties'] as Map<String, dynamic>? ?? {};
        final geom  = f['geometry']  as Map<String, dynamic>? ?? {};
        final coords = (geom['coordinates'] as List?)?.cast<dynamic>();
        final pLng = (coords?.isNotEmpty == true) ? (coords![0] as num?)?.toDouble() : null;
        final pLat = (coords?.length == 2)        ? (coords![1] as num?)?.toDouble() : null;

        final street = props['street'] as String? ?? '';
        final city   = props['city']   as String? ?? '';
        final name   = props['name']   as String? ?? query;
        final mainText = name.isNotEmpty ? name : (street.isNotEmpty ? street : city);
        final secondary = [
          if (street.isNotEmpty && street != mainText) street,
          if (city.isNotEmpty) city,
        ].join(', ');

        final fullText = [mainText, if (secondary.isNotEmpty) secondary].join(', ');

        return SmartMapsResult(
          placeId:       props['id']?.toString() ?? fullText,
          mainText:      mainText,
          secondaryText: secondary,
          fullText:      fullText,
          lat:           pLat,
          lng:           pLng,
        );
      }).where((r) => r.lat != null && r.lng != null).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Forward geocode ────────────────────────────────────────────────────────

  static Future<({String address, double lat, double lng})?> geocode(
    String address,
  ) async {
    if (!isAvailable) return null;
    try {
      final resp = await _geocode.post(
        '/api_rst/v2/geojson/geocode',
        queryParameters: {'apiKey': _apiKey},
        options: Options(headers: {'Content-Type': 'application/json'}),
        data: {
          'singleSlot': address,
          'geocodingType': 'GEOCODE',
          'coordFormatOut': 'GEODECIMAL_POINT',
          'channel': 'binlink',
        },
      );
      final feature = _firstFeature(resp.data);
      if (feature == null) return null;
      final geom  = feature['geometry'] as Map<String, dynamic>? ?? {};
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      final coords = (geom['coordinates'] as List?)?.cast<dynamic>();
      if (coords == null || coords.length < 2) return null;
      final fLng = jsonDouble(coords[0]);
      final fLat = jsonDouble(coords[1]);
      if (fLat == null || fLng == null) return null;
      final freeform = _buildAddress(props);
      return (address: freeform.isEmpty ? address : freeform, lat: fLat, lng: fLng);
    } catch (_) {
      return null;
    }
  }

  // ── Reverse geocode ────────────────────────────────────────────────────────

  static Future<String?> reverseGeocode(double lat, double lng) async {
    if (!isAvailable) return null;
    try {
      final resp = await _geocode.post(
        '/api_rst/v2/geojson/geocode',
        queryParameters: {'apiKey': _apiKey},
        options: Options(headers: {'Content-Type': 'application/json'}),
        data: {
          'geocodingType': 'REVERSE_GEOCODE',
          'coordFormatOut': 'GEODECIMAL_POINT',
          'channel': 'binlink',
          'geometry': {
            'type': 'Point',
            'coordinates': [lng, lat],
          },
        },
      );
      final feature = _firstFeature(resp.data);
      if (feature == null) return null;
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      return _buildAddress(props).nullIfEmpty();
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _extractFeatures(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map) {
      final fc = data['features'];
      if (fc is List) return fc.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  static Map<String, dynamic>? _firstFeature(dynamic data) {
    final features = _extractFeatures(data);
    return features.isNotEmpty ? features.first : null;
  }

  static String _buildAddress(Map<String, dynamic> props) {
    final parts = <String>[];
    final street = props['street'] as String?;
    final houseNo = props['houseNo'] as String?;
    final city = props['city'] as String?;
    final district = props['district'] as String?;
    final country = props['country'] as String?;
    if (street != null && street.isNotEmpty) {
      parts.add(houseNo != null ? '$street $houseNo' : street);
    }
    if (city != null && city.isNotEmpty) {
      parts.add(city);
    } else if (district != null && district.isNotEmpty) {
      parts.add(district);
    }
    if (country != null && country.isNotEmpty) { parts.add(country); }
    return parts.join(', ');
  }
}

extension _StringX on String {
  String? nullIfEmpty() => isEmpty ? null : this;
}
