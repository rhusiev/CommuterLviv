import 'dart:ui' as ui;

import 'package:commuterlviv/src/basemap_style.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile/vector_tile.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' hide VectorTile;

const _extent = 4096;
const _green = [0, 128, 0];

/// One `land` polygon of [kind] over the whole tile.
VectorTile _land(String kind) {
  int zigzag(int n) => (n << 1) ^ (n >> 31);
  const moveTo = 9, lineTo3 = 26, close = 15;
  return VectorTile(
    layers: [
      VectorTileLayer(
        name: 'land',
        extent: _extent,
        version: 2,
        keys: ['kind'],
        values: [VectorTileValue(stringValue: kind)],
        features: [
          VectorTileFeature(
            id: Int64(1),
            tags: [0, 0],
            type: VectorTileGeomType.POLYGON,
            geometryList: [
              moveTo, 0, 0, //
              lineTo3, zigzag(_extent), 0, 0, zigzag(_extent),
              zigzag(-_extent), 0, //
              close,
            ],
            extent: _extent,
            keys: ['kind'],
            values: [VectorTileValue(stringValue: kind)],
          ),
        ],
      ),
    ],
  );
}

/// A style as VersaTiles writes it: parks found by `in` a literal list.
Map<String, dynamic> _style() => {
  'version': 8,
  'sources': {
    'osm': {'type': 'vector'},
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': 'rgb(255,255,255)'},
    },
    {
      'id': 'land-park',
      'type': 'fill',
      'source': 'osm',
      'source-layer': 'land',
      'filter': [
        'in',
        ['get', 'kind'],
        [
          'literal',
          ['park', 'forest'],
        ],
      ],
      'paint': {'fill-color': 'rgb(${_green.join(',')})'},
    },
  ],
};

Future<List<int>> _middle(Map<String, dynamic> style, String kind) async {
  final theme = ThemeReader().read(style);
  final tile = TileFactory(theme, const Logger.noop()).create(_land(kind));
  final image = await ImageRenderer(
    theme: theme,
    scale: 1,
  ).render(TileSource(tileset: Tileset({'osm': tile})), zoom: 15);
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final at = (image.height ~/ 2 * image.width + image.width ~/ 2) * 4;
  return [for (var i = 0; i < 3; i++) rgba.getUint8(at + i)];
}

void main() {
  test(
    'an in-a-literal-list filter becomes a match, wherever it is nested',
    () {
      final style = readable({
        'filter': [
          'all',
          [
            'in',
            ['get', 'kind'],
            [
              'literal',
              ['rail', 'tram'],
            ],
          ],
          [
            '==',
            ['get', 'tunnel'],
            true,
          ],
        ],
      });

      expect(style['filter'], [
        'all',
        [
          'match',
          ['get', 'kind'],
          ['rail', 'tram'],
          true,
          false,
        ],
        [
          '==',
          ['get', 'tunnel'],
          true,
        ],
      ]);
    },
  );

  testWidgets('a park the style fills is drawn, and other land is not', (
    tester,
  ) async {
    await tester.runAsync(() async {
      expect(await _middle(readable(_style()), 'park'), _green);
      expect(await _middle(readable(_style()), 'residential'), [255, 255, 255]);
    });
  });
}
