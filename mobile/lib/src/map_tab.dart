/// The city, the vehicles on it, and nothing that knows where they came from.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'here.dart';
import 'live.dart';
import 'map_controls.dart';
import 'map_theme.dart';
import 'map_tiles.dart';
import 'models.dart';
import 'theme.dart';
import 'vehicle_layer.dart';
import 'strings.dart';

const lviv = LatLng(49.8397, 24.0297);

class MapTab extends StatelessWidget {
  const MapTab({
    super.key,
    required this.map,
    required this.style,
    required this.catalog,
    required this.live,
    required this.stops,
    required this.selected,
    required this.theme,
    required this.here,
    required this.empty,
    required this.marks,
    required this.shapes,
    required this.lines,
    required this.arrowed,
    required this.onTap,
  });

  final MapController map;

  /// Null while the basemap is still being read.
  final Style? style;
  final Catalog catalog;
  final Live live;
  final List<int> stops;
  final int? selected;
  final MapTheme theme;

  final Here here;

  final bool empty;

  /// The ends of a journey being planned, lettered rather than coloured.
  final List<({LatLng at, String label})> marks;

  /// Every route's geometry; `arrowed` is the one route that gets arrows.
  final Shapes? shapes;
  final List<int> lines;
  final int? arrowed;
  final void Function(LatLng point) onTap;

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
            ),
            if (marks.isNotEmpty)
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
        Positioned(
          right: floatingGap,
          bottom: floatingBottom(context),
          child: MapControls(map: map, here: here),
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
