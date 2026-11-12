/// Where the basemap is kept between runs. `vector_map_tiles` defaults to the
/// temporary directory, which on Android the system empties at will, so tiles
/// go under application support instead.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'map_theme.dart';

/// How long a tile is used before it is fetched again.
const tileTtl = Duration(days: 90);

/// Room for the whole city, which is a few tens of megabytes.
const tileDiskBytes = 200 * 1024 * 1024;

/// In-memory tile bytes and parsed tiles, for the pan back to where you were.
const tileMemoryBytes = 32 * 1024 * 1024;
const tileMemoryCount = 50;

Future<Directory> tileCache() async =>
    tileCacheIn(await getApplicationSupportDirectory());

/// The cache of the basemap's current generation, under [base], with the tiles
/// of every other generation dropped: they are of a map nobody is served now.
/// Older builds kept the tiles flat under `tiles/`, which this clears too.
Future<Directory> tileCacheIn(Directory base) async {
  final root = await Directory('${base.path}/tiles').create(recursive: true);
  final generation = tileGeneration.isEmpty ? 'unversioned' : tileGeneration;
  await dropOlder(root, generation);
  return Directory('${root.path}/$generation').create(recursive: true);
}

/// Everything under [root] but the folder [keep], which is dropped the first
/// time a cache is asked for in this run.
Future<void> dropOlder(Directory root, String keep) async {
  await for (final entry in root.list()) {
    if (entry.path.split(Platform.pathSeparator).last == keep) continue;
    try {
      await entry.delete(recursive: true);
    } on FileSystemException {
      // gone already, or a tile being written: the next run takes it
    }
  }
}
