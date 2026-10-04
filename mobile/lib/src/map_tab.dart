/// The city, the vehicles on it, and nothing that knows where they came from.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'api.dart';
import 'here.dart';
import 'journey_layer.dart';
import 'live.dart';
import 'map_controls.dart';
import 'map_theme.dart';
import 'map_tiles.dart';
import 'models.dart';
import 'theme.dart';
import 'traffic.dart';
import 'vehicle_layer.dart';
import 'strings.dart';

const lviv = LatLng(49.8397, 24.0297);

class MapTab extends StatelessWidget {
  const MapTab({
    super.key,
    required this.api,
    required this.map,
    required this.style,
    required this.traffic,
    required this.catalog,
    required this.live,
    required this.stops,
    required this.selected,
    required this.theme,
    required this.here,
    this.onLocate,
    required this.empty,
    required this.marks,
    required this.journey,
    required this.pins,
    required this.places,
    required this.shapes,
    required this.lines,
    required this.arrowed,
    required this.onTap,
    required this.onHold,
  });

  final Api api;
  final MapController map;

  /// Null while the basemap is still being read.
  final Style? style;

  /// How the streets are running, over the basemap and under everything else.
  /// Only while this is on is anything asked for.
  final bool traffic;
  final Catalog catalog;
  final Live live;
  final List<int> stops;
  final int? selected;
  final MapTheme theme;

  final Here here;

  /// Also run by the locate button, after it has moved to the dot.
  final VoidCallback? onLocate;

  final bool empty;

  /// The ends of a journey being planned, lettered rather than coloured.
  final List<({LatLng at, String label})> marks;
  final Journey? journey;

  /// What the account kept, always on the map: pinned stops ringed, saved places
  /// as named dots.
  final List<int> pins;
  final List<Place> places;

  /// Every route's geometry; `arrowed` is the one route that gets arrows.
  final Shapes? shapes;
  final List<int> lines;
  final int? arrowed;
  final void Function(LatLng point) onTap;
  final void Function(LatLng point) onHold;

  @override
  Widget build(BuildContext context) {
    final style = this.style;
    final ink = Palette.of(theme.dark);
    return Stack(
      children: [
        FlutterMap(
          mapController: map,
          options: MapOptions(
            initialCenter: lviv,
            initialZoom: 13,
            minZoom: minZoom,
            maxZoom: maxZoom,
            onTap: (_, point) => onTap(point),
            onLongPress: (_, point) => onHold(point),
            interactionOptions: mapInteraction,
          ),
          children: [
            if (style != null)
              VectorTileLayer(
                tileProviders: style.providers,
                theme: style.theme,
                sprites: style.sprites,
                // The renderer drops detail rather than the frame past this
                maximumZoom: 18,
                // `analyze` resolves the package's conditional export to its
                // web stub, where its `Directory` is a `String`; the compiler
                // picks the `dart:io` one this actually gets
                // ignore: argument_type_not_assignable
                cacheFolder: tileCache,
                fileCacheTtl: tileTtl,
                fileCacheMaximumSizeInBytes: tileDiskBytes,
                memoryTileCacheMaxSize: tileMemoryBytes,
                memoryTileDataCacheMaxSize: tileMemoryCount,
              ),
            if (traffic) TrafficLayer(api: api),
            VehicleLayer(
              catalog: catalog,
              live: live,
              stops: stops,
              selected: selected,
              theme: theme,
              here: here,
              shapes: shapes,
              lines: lines,
              arrowed: arrowed,
              pins: pins,
              places: places,
            ),
            if (journey case final journey?)
              JourneyLayer(journey: journey, catalog: catalog, theme: theme),
            // The journey's own pills name its ends while it is drawn.
            if (journey == null && marks.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final mark in marks)
                    Marker(
                      point: mark.at,
                      width: 26,
                      height: 26,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ink.nub,
                          border: Border.all(color: ink.edge, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            mark.label,
                            style: TextStyle(
                              color: ink.edge,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            const _Attribution(),
          ],
        ),
        // Android's own swipes (home, back) start in these strips; left to the
        // map, a swipe up to leave the app also drags it
        ..._gestureStrips(MediaQuery.systemGestureInsetsOf(context)),
        Positioned(
          right: floatingGap,
          bottom: floatingBottom(context),
          child: MapControls(map: map, here: here, onLocate: onLocate),
        ),
        if (style == null) const LinearProgressIndicator(minHeight: 2),
        if (empty)
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(txt.pickARoute),
              ),
            ),
          ),
      ],
    );
  }
}

Iterable<Widget> _gestureStrips(EdgeInsets inset) => [
  if (inset.bottom > 0)
    Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: inset.bottom,
      child: _absorb,
    ),
  if (inset.left > 0)
    Positioned(left: 0, top: 0, bottom: 0, width: inset.left, child: _absorb),
  if (inset.right > 0)
    Positioned(right: 0, top: 0, bottom: 0, width: inset.right, child: _absorb),
];

const _absorb = AbsorbPointer(child: SizedBox.expand());

/// Map attribution. OpenStreetMap's ODbL guidelines allow the credit to sit
/// one tap inside an icon on a small screen, provided the icon is always
/// visible and the credit is a link.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) => RichAttributionWidget(
    alignment: AttributionAlignment.bottomLeft,
    showFlutterMapAttribution: false,
    attributions: [
      TextSourceAttribution(
        'OpenStreetMap',
        onTap: () => _open('https://www.openstreetmap.org/copyright'),
      ),
      TextSourceAttribution(
        'VersaTiles',
        onTap: () => _open('https://versatiles.org/'),
      ),
    ],
  );

  void _open(String url) => unawaited(
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
  );
}
