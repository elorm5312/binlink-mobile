import 'package:dio/dio.dart';
import '../config/env.dart';
import 'smartmaps_service.dart';

class PlacePrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String fullText;
  final double? lat;
  final double? lng;

  const PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
    this.lat,
    this.lng,
  });
}

class PlaceDetail {
  final String address;
  final double lat;
  final double lng;

  const PlaceDetail({
    required this.address,
    required this.lat,
    required this.lng,
  });
}

/// Location intelligence — SmartMaps → TomTom → Nominatim cascade.
class PlacesService {
  PlacesService._();

  static final _ttDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  static final _nominatim = Dio(BaseOptions(
    baseUrl: 'https://nominatim.openstreetmap.org',
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      'User-Agent': 'BinLinkEco/2.0 (binlinkeco@gmail.com)',
      'Accept-Language': 'en',
    },
  ));

  static String get _ttKey => Env.tomtomApiKey;
  static bool get _hasTomTom => _ttKey.isNotEmpty;

  // ── Autocomplete ───────────────────────────────────────────────────────────

  static Future<List<PlacePrediction>> autocomplete(
    String input, {
    double lat = 5.6037,
    double lng = -0.1870,
  }) async {
    if (input.trim().length < 2) return [];

    // 1. SmartMaps
    if (SmartMapsService.isAvailable) {
      final results = await SmartMapsService.autocomplete(input, lat: lat, lng: lng);
      if (results.isNotEmpty) {
        return results.map((r) => PlacePrediction(
          placeId:       r.placeId,
          mainText:      r.mainText,
          secondaryText: r.secondaryText,
          fullText:      r.fullText,
          lat:           r.lat,
          lng:           r.lng,
        )).toList();
      }
    }

    // 2. TomTom
    if (_hasTomTom) {
      final results = await _tomtomSearch(input, lat: lat, lng: lng);
      if (results.isNotEmpty) return results;
    }

    // 3. Nominatim
    return _nominatimSearch(input, lat: lat, lng: lng);
  }

  static Future<List<PlacePrediction>> _tomtomSearch(
    String query, {
    required double lat,
    required double lng,
  }) async {
    try {
      final resp = await _ttDio.get(
        'https://api.tomtom.com/search/2/search/${Uri.encodeComponent(query)}.json',
        queryParameters: {
          'key': _ttKey,
          'limit': 5,
          'countrySet': 'GH',
          'lat': lat,
          'lon': lng,
          'radius': 50000,
          'language': 'en-GB',
        },
      );
      final results = (resp.data['results'] as List?) ?? [];
      return results.map((r) {
        final addr = r['address'] as Map<String, dynamic>? ?? {};
        final pos  = r['position'] as Map<String, dynamic>? ?? {};
        final freeform     = addr['freeformAddress'] as String? ?? '';
        final municipality = addr['municipality']   as String? ?? '';
        final country      = addr['country']        as String? ?? 'Ghana';
        final streetName   = addr['streetName']     as String? ?? '';
        final mainText = streetName.isNotEmpty ? streetName
            : municipality.isNotEmpty ? municipality
            : freeform;
        final secondary = municipality.isNotEmpty && municipality != mainText
            ? '$municipality, $country'
            : country;
        return PlacePrediction(
          placeId:       r['id'] as String? ?? freeform,
          mainText:      mainText,
          secondaryText: secondary,
          fullText:      freeform.isEmpty ? query : freeform,
          lat:           (pos['lat'] as num?)?.toDouble(),
          lng:           (pos['lon'] as num?)?.toDouble(),
        );
      }).where((p) => p.lat != null && p.lat! != 0).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<PlacePrediction>> _nominatimSearch(
    String query, {
    required double lat,
    required double lng,
  }) async {
    try {
      final resp = await _nominatim.get('/search', queryParameters: {
        'q':              query,
        'format':         'json',
        'countrycodes':   'gh',
        'limit':          5,
        'addressdetails': 1,
        'accept-language':'en',
        'viewbox':        '${lng - 0.5},${lat - 0.5},${lng + 0.5},${lat + 0.5}',
        'bounded':        1,
      });
      final items = (resp.data as List?) ?? [];
      return items.map((r) {
        final displayName = r['display_name'] as String? ?? '';
        final parts = displayName.split(', ');
        return PlacePrediction(
          placeId:       r['place_id'].toString(),
          mainText:      parts.isNotEmpty ? parts[0] : displayName,
          secondaryText: parts.length > 1 ? parts.skip(1).take(2).join(', ') : '',
          fullText:      displayName,
          lat:           double.tryParse(r['lat'] as String? ?? ''),
          lng:           double.tryParse(r['lon'] as String? ?? ''),
        );
      }).where((p) => p.lat != null && p.lat! != 0).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Detail lookup ──────────────────────────────────────────────────────────

  static Future<PlaceDetail?> getDetail(String placeId) async {
    if (SmartMapsService.isAvailable) {
      final r = await SmartMapsService.geocode(placeId);
      if (r != null) return PlaceDetail(address: r.address, lat: r.lat, lng: r.lng);
    }
    if (_hasTomTom) {
      try {
        final resp = await _ttDio.get(
          'https://api.tomtom.com/search/2/geocode/${Uri.encodeComponent(placeId)}.json',
          queryParameters: {'key': _ttKey, 'limit': 1, 'countrySet': 'GH'},
        );
        final results = (resp.data['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          final r   = results.first as Map<String, dynamic>;
          final pos = r['position'] as Map<String, dynamic>? ?? {};
          final addr = r['address'] as Map<String, dynamic>? ?? {};
          return PlaceDetail(
            address: addr['freeformAddress'] as String? ?? placeId,
            lat:     (pos['lat'] as num).toDouble(),
            lng:     (pos['lon'] as num).toDouble(),
          );
        }
      } catch (_) {}
    }
    try {
      final resp = await _nominatim.get('/reverse', queryParameters: {
        'place_id': placeId, 'format': 'json', 'accept-language': 'en',
      });
      final lat = double.tryParse(resp.data['lat']?.toString() ?? '');
      final lng = double.tryParse(resp.data['lon']?.toString() ?? '');
      if (lat != null && lng != null) {
        return PlaceDetail(
          address: resp.data['display_name'] as String? ?? placeId,
          lat: lat, lng: lng,
        );
      }
    } catch (_) {}
    return null;
  }

  // ── Reverse geocode ────────────────────────────────────────────────────────

  static Future<String?> reverseGeocode(double lat, double lng) async {
    if (SmartMapsService.isAvailable) {
      final addr = await SmartMapsService.reverseGeocode(lat, lng);
      if (addr != null && addr.isNotEmpty) return addr;
    }
    if (_hasTomTom) {
      try {
        final resp = await _ttDio.get(
          'https://api.tomtom.com/search/2/reverseGeocode/$lat,$lng.json',
          queryParameters: {'key': _ttKey, 'language': 'en-GB'},
        );
        final addresses = (resp.data['addresses'] as List?) ?? [];
        if (addresses.isNotEmpty) {
          final addr = addresses.first['address']?['freeformAddress'] as String?;
          if (addr != null && addr.isNotEmpty) return addr;
        }
      } catch (_) {}
    }
    try {
      final resp = await _nominatim.get('/reverse', queryParameters: {
        'lat': lat, 'lon': lng, 'format': 'json', 'accept-language': 'en',
      });
      return resp.data['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }
}
