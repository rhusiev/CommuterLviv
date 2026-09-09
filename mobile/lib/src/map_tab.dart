/// The city, the vehicles on it, and nothing that knows where they came from.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'live.dart';
import 'map_controls.dart';
import 'map_theme.dart';
import 'map_tiles.dart';
import 'models.dart';
import 'vehicle_layer.dart';

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
    required this.empty,
    required this.onTap,
  });

  final MapController map;

  /// Null while the basemap is still being read; the vehicles are drawn over
  /// nothing until it arrives, which is better than an empty screen
  final Style? style;
  final Catalog catalog;
  final Live live;
  final List<int> stops;
  final int? selected;
  final MapTheme theme;

  /// Whether no route is chosen, which is the one state worth explaining
  final bool empty;
  final void Function(LatLng point) onTap;

  @override
  Widget build(BuildContext context) {
    final style = this.style;
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
                // The renderer's own frame budget: below this it drops detail
                // rather than the frame, which is the right trade on a phone
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
            ),
            const SimpleAttributionWidget(
              source: Text('OpenStreetMap · VersaTiles'),
              alignment: Alignment.bottomLeft,
            ),
          ],
        ),
        Positioned(right: 12, bottom: 24, child: MapControls(map: map)),
        if (style == null) const LinearProgressIndicator(minHeight: 2),
        if (empty)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Pick a route to see it moving'),
              ),
            ),
          ),
      ],
    );
  }
}
