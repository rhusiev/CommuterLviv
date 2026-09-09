/// Where the basemap is kept between runs.
///
/// `vector_map_tiles` caches rendered tiles on disk already, but under the
/// temporary directory - which on Android is the cache directory the system
/// empties whenever it wants space, and which "Clear cache" wipes. A rider on
/// the tram with no signal is exactly the person who needs the tiles that were
/// there yesterday, so they are kept under application support instead, where
/// only an uninstall removes them.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// How long a tile is used before it is fetched again. The city's streets are
/// not what changes about this map - the vehicles on top of it are, and they
/// do not come from here.
const tileTtl = Duration(days: 90);

/// Lviv at every zoom the app draws is a few tens of megabytes; this is room
/// for the whole city rather than a window onto it.
const tileDiskBytes = 200 * 1024 * 1024;

/// Raw tile bytes held in memory, and parsed tiles kept beside them. Both are
/// for the pan back to where you just were, which should cost nothing.
const tileMemoryBytes = 32 * 1024 * 1024;
const tileMemoryCount = 50;

Future<Directory> tileCache() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/tiles').create(recursive: true);
}
