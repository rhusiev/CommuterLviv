import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/map_theme.dart';
import 'package:commuterlviv/src/map_tiles.dart';

void main() {
  late Directory base;
  setUp(() async {
    base = await Directory.systemTemp.createTemp('tiles-test');
    addTearDown(() => base.delete(recursive: true));
  });

  test('the cache is a folder named for the basemap generation', () async {
    setTileGeneration('1794481253');
    addTearDown(() => setTileGeneration(null));

    final dir = await tileCacheIn(base);

    expect(dir.path, endsWith('tiles/1794481253'));
    expect(dir.existsSync(), isTrue);
  });

  test('the tiles of every other generation are dropped', () async {
    final older = Directory('${base.path}/tiles/1700000000')
      ..createSync(recursive: true);
    File('${older.path}/14_9285_5569_osm.pbf').writeAsStringSync('older');
    // what builds before the generation kept, flat under `tiles/`
    final flat = Directory('${base.path}/tiles');
    flat.createSync(recursive: true);
    File('${flat.path}/14_9285_5569_osm.pbf').writeAsStringSync('flat');
    setTileGeneration('1794481253');
    addTearDown(() => setTileGeneration(null));

    await tileCacheIn(base);

    expect(older.existsSync(), isFalse);
    expect(File('${flat.path}/14_9285_5569_osm.pbf').existsSync(), isFalse);
    expect(Directory('${base.path}/tiles/1794481253').existsSync(), isTrue);
  });

  test('without a generation the folder says so', () async {
    setTileGeneration(null);

    final dir = await tileCacheIn(base);

    expect(dir.path, endsWith('tiles/unversioned'));
  });
}
