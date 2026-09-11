/// Where the basemap is kept between runs. `vector_map_tiles` defaults to the
/// temporary directory, which on Android the system empties at will, so tiles
/// go under application support instead.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// How long a tile is used before it is fetched again.
const tileTtl = Duration(days: 90);

/// Room for the whole city, which is a few tens of megabytes.
const tileDiskBytes = 200 * 1024 * 1024;

/// In-memory tile bytes and parsed tiles, for the pan back to where you were.
const tileMemoryBytes = 32 * 1024 * 1024;
const tileMemoryCount = 50;

Future<Directory> tileCache() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/tiles').create(recursive: true);
}
