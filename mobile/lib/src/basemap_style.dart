/// The basemap style's theme, with its `["in", x, ["literal", [...]]]`
/// filters written as the `match` the tile renderer can read (docs/clients.md).
library;

import 'dart:convert';
import 'dart:io';

import 'package:vector_tile_renderer/vector_tile_renderer.dart';

/// The style JSON with every `in`-a-literal-list rewritten as a `match`.
dynamic readable(dynamic json) {
  if (json is Map) {
    return <String, dynamic>{
      for (final e in json.entries) e.key as String: readable(e.value),
    };
  }
  if (json is! List) return json;
  final values = _literalList(json);
  if (values != null) return ['match', readable(json[1]), values, true, false];
  return [for (final v in json) readable(v)];
}

List<dynamic>? _literalList(List<dynamic> json) {
  if (json.length != 3 || json[0] != 'in') return null;
  final set = json[2];
  if (set is! List || set.length != 2 || set[0] != 'literal') return null;
  final values = set[1];
  return values is List ? values : null;
}

/// The theme of the style at [url], fetched and read through [readable].
Future<Theme> readTheme(String url) async {
  final http = HttpClient();
  try {
    final res = await (await http.getUrl(Uri.parse(url))).close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != HttpStatus.ok) {
      throw HttpException(
        'style answered ${res.statusCode}',
        uri: Uri.parse(url),
      );
    }
    return ThemeReader().read(readable(jsonDecode(body)));
  } finally {
    http.close();
  }
}
