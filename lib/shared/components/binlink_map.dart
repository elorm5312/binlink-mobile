import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../core/config/env.dart';
import '../../core/config/app_flavor.dart';
import '../../core/design_system/collector_design_system.dart';
import '../../core/design_system/household_design_system.dart';

class MapStyleResolver {
  MapStyleResolver._();

  static const fallbackStyleUrl = 'https://tiles.openfreemap.org/styles/dark';
  static String? _resolved;
  static Future<String>? _inFlight;

  static Future<String> resolve() {
    if (_resolved != null) return Future.value(_resolved);
    return _inFlight ??= _probe();
  }

  static Future<String> _probe() async {
    final key = Env.smartmapsApiKey;
    if (key.isNotEmpty) {
      final url = 'https://tiles.smartmaps.cloud/styles/v1/smartmaps/dark/style.json?apiKey=${Uri.encodeComponent(key)}';
      try {
        final res = await Dio().get<void>(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 6),
            sendTimeout: const Duration(seconds: 6),
            validateStatus: (s) => true,
          ),
        );
        if (res.statusCode == 200) {
          _resolved = url;
          return url;
        }
      } catch (e) {
        debugPrint('[Map] SmartMaps style probe failed: $e');
      }
    }
    _resolved = fallbackStyleUrl;
    return fallbackStyleUrl;
  }
}

class BinLinkMap extends StatefulWidget {
  const BinLinkMap({
    super.key,
    required this.initialPosition,
    this.collectors = const [],
    this.routePoints = const [],
    this.pickupPosition,
    this.onMapCreated,
    this.myLocationEnabled = true,
    this.padding = EdgeInsets.zero,
    this.onCollectorTap,
    this.initialZoom = 14.5,
    this.isNavigating = false,
    this.myLocation,
    this.myHeading = 0.0,
  });

  final ll.LatLng initialPosition;
  final List<Map<String, dynamic>> collectors;
  final List<ll.LatLng> routePoints;
  final ll.LatLng? pickupPosition;
  final Function(MapLibreMapController)? onMapCreated;
  final bool myLocationEnabled;
  final EdgeInsets padding;
  final Function(Map<String, dynamic>)? onCollectorTap;
  final double initialZoom;
  final bool isNavigating;
  final ll.LatLng? myLocation;
  final double myHeading;

  @override
  State<BinLinkMap> createState() => BinLinkMapState();
}

class BinLinkMapState extends State<BinLinkMap> {
  MapLibreMapController? _controller;
  bool _styleLoaded = false;
  String? _styleUrl;

  // Track which layers are already added so we update sources in place
  // (smooth, cheap) instead of removing/re-adding on every GPS tick.
  bool _collectorReady = false;
  bool _routeReady = false;
  bool _pickupReady = false;
  bool _didInitialFit = false;

  @override
  void initState() {
    super.initState();
    MapStyleResolver.resolve().then((url) {
      if (mounted) setState(() => _styleUrl = url);
    });
  }

  @override
  void didUpdateWidget(covariant BinLinkMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_styleLoaded) {
      _updateMapLayers(oldWidget);
    }
  }

  void flyTo(ll.LatLng position, {double zoom = 15}) {
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        zoom,
      ),
    );
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    widget.onMapCreated?.call(controller);
  }

  Future<Uint8List> _loadAssetImage(String path, {int width = 120}) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    final fi = await codec.getNextFrame();
    final imgData = await fi.image.toByteData(format: ui.ImageByteFormat.png);
    return imgData!.buffer.asUint8List();
  }

  void _onStyleLoaded() async {
    _styleLoaded = true;
    try {
      await _controller?.addImage('truck-icon', await _loadAssetImage(FlavorConfig.isCollector ? CollectorAssets.truckMarker : HouseholdAssets.truckMarker, width: 140));
      await _controller?.addImage('pickup-pin', await _loadAssetImage(FlavorConfig.isCollector ? CollectorAssets.pickupMarker : HouseholdAssets.pickupMarker, width: 120));
    } catch (e) {
      debugPrint('[Map] Failed to add branded markers: $e');
    }
    _updateMapLayers(null);
  }

  void _updateMapLayers(BinLinkMap? oldWidget) {
    if (_controller == null || !_styleLoaded) return;
    try {
      final routeChanged = widget.routePoints != oldWidget?.routePoints;
      final collectorsChanged = widget.collectors != oldWidget?.collectors;
      if (routeChanged) _drawRoute();
      if (collectorsChanged) _updateCollectors();
      if (widget.pickupPosition != oldWidget?.pickupPosition) _updatePickupPin();

      if (widget.isNavigating && widget.myLocation != null) {
        // Collector's own turn-by-turn view: follow their location + heading.
        _controller?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(widget.myLocation!.latitude, widget.myLocation!.longitude),
              zoom: 17.5,
              bearing: widget.myHeading,
              tilt: 45,
            ),
          ),
        );
      } else if (routeChanged || (collectorsChanged && !_didInitialFit)) {
        // Household tracking view: keep both the collector and the pickup in
        // frame — re-fit when the route recomputes (collector moved ~150m).
        _fitToContent();
      }
    } catch (e) {
      debugPrint('[Map] Error updating layers: $e');
    }
  }

  /// Zoom/pan so both the pickup and the collector(s) stay visible, with room
  /// for the top status bar and the bottom card. Uber/Bolt-style framing.
  void _fitToContent() {
    if (_controller == null || !_styleLoaded || widget.isNavigating) return;
    final pts = <ll.LatLng>[];
    if (widget.pickupPosition != null) pts.add(widget.pickupPosition!);
    for (final c in widget.collectors) {
      final lat = (c['lastLat'] as num?)?.toDouble();
      final lng = (c['lastLng'] as num?)?.toDouble();
      if (lat != null && lng != null) pts.add(ll.LatLng(lat, lng));
    }
    if (pts.length < 2) return;
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    _didInitialFit = true;
    _controller?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        left: 60, right: 60, top: 170, bottom: 300,
      ),
    );
  }

  void _drawRoute() async {
    if (_controller == null || !_styleLoaded) return;
    const sourceId = 'route-source';

    final coordinates = widget.routePoints.map((p) => [p.longitude, p.latitude]).toList();
    final data = <String, dynamic>{
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, dynamic>{},
          'geometry': {'type': 'LineString', 'coordinates': coordinates},
        },
      ],
    };

    try {
      // Update in place if the layers already exist (smooth, no flicker).
      if (_routeReady) {
        await _controller?.setGeoJsonSource(sourceId, data);
        return;
      }
      if (widget.routePoints.isEmpty) return;

      final accent = (FlavorConfig.isCollector ? CollectorColors.green : HouseholdColors.primary).toHexShortString();
      await _controller?.addSource(sourceId, GeojsonSourceProperties(data: data));
      // Dark casing underneath gives the route a crisp, map-app look.
      await _controller?.addLineLayer(sourceId, 'route-casing', const LineLayerProperties(
        lineColor: '#0D1821', lineWidth: 9.5, lineJoin: 'round', lineCap: 'round', lineOpacity: 0.55));
      await _controller?.addLineLayer(sourceId, 'route-line', LineLayerProperties(
        lineColor: accent, lineWidth: 5.5, lineJoin: 'round', lineCap: 'round'));
      _routeReady = true;
    } catch (e) {
      debugPrint('[Map] Error drawing route: $e');
    }
  }

  void _updateCollectors() async {
    if (_controller == null || !_styleLoaded) return;
    const layerId = 'collector-layer';
    const sourceId = 'collector-source';

    final features = <Map<String, dynamic>>[];
    for (final c in widget.collectors) {
      final lat = (c['lastLat'] as num?)?.toDouble();
      final lng = (c['lastLng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [lng, lat],
        },
        'properties': {
          'id': c['id'],
          'bearing': (c['bearing'] as num?)?.toDouble() ?? 0.0,
        },
      });
    }
    final data = <String, dynamic>{'type': 'FeatureCollection', 'features': features};

    try {
      // Update the source in place so the truck glides instead of blinking.
      if (_collectorReady) {
        await _controller?.setGeoJsonSource(sourceId, data);
        return;
      }
      if (features.isEmpty) return;

      await _controller?.addSource(sourceId, GeojsonSourceProperties(data: data));
      await _controller?.addSymbolLayer(
        sourceId,
        layerId,
        const SymbolLayerProperties(
          iconImage: 'truck-icon',
          iconSize: 0.6,
          // Rotate the truck to its travel heading, aligned with the map.
          iconRotate: ['get', 'bearing'],
          iconRotationAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );
      _collectorReady = true;
    } catch (e) {
      debugPrint('[Map] Error updating collectors: $e');
    }
  }

  void _updatePickupPin() async {
    if (_controller == null || !_styleLoaded) return;
    const layerId = 'pickup-layer';
    const sourceId = 'pickup-source';

    final pos = widget.pickupPosition;
    if (pos == null && !_pickupReady) return;

    final data = <String, dynamic>{
      'type': 'FeatureCollection',
      'features': pos == null
          ? <Map<String, dynamic>>[]
          : [
              {
                'type': 'Feature',
                'properties': <String, dynamic>{},
                'geometry': {
                  'type': 'Point',
                  'coordinates': [pos.longitude, pos.latitude],
                },
              },
            ],
    };

    try {
      if (_pickupReady) {
        await _controller?.setGeoJsonSource(sourceId, data);
        return;
      }
      await _controller?.addSource(sourceId, GeojsonSourceProperties(data: data));
      await _controller?.addSymbolLayer(
        sourceId,
        layerId,
        const SymbolLayerProperties(
          iconImage: 'pickup-pin',
          iconSize: 0.8,
          iconAllowOverlap: true,
        ),
      );
      _pickupReady = true;
    } catch (e) {
      debugPrint('[Map] Error updating pickup pin: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final styleUrl = _styleUrl;
    if (styleUrl == null) {
      return Container(color: FlavorConfig.isCollector ? CollectorColors.dark : HouseholdColors.sand);
    }

    return MapLibreMap(
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.initialPosition.latitude, widget.initialPosition.longitude),
        zoom: widget.initialZoom,
      ),
      styleString: styleUrl,
      myLocationEnabled: widget.myLocationEnabled,
      myLocationRenderMode: MyLocationRenderMode.compass,
      myLocationTrackingMode: widget.isNavigating
          ? MyLocationTrackingMode.trackingGps
          : MyLocationTrackingMode.none,
      trackCameraPosition: true,
      onMapClick: (point, latlng) async {
        final features = await _controller?.queryRenderedFeatures(
          point,
          ['collector-layer'],
          null,
        );
        if (features != null && features.isNotEmpty) {
          final id = features.first['properties']['id'];
          final collector = widget.collectors.firstWhere((c) => c['id'] == id, orElse: () => {});
          if (collector.isNotEmpty) {
            widget.onCollectorTap?.call(collector);
          }
        }
      },
    );
  }
}

extension _ColorX on Color {
  String toHexShortString() {
    final argb = toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}
