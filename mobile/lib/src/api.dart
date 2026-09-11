/// Talking to `commuterlviv serve`. The service authenticates as a browser
/// does, so this is a cookie jar, an `Origin` header and a CSRF echo.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'map_theme.dart';
import 'models.dart';

/// Must be listed in the server's `COMMUTERLVIV_ORIGINS`.
const appOrigin = 'app://commuterlviv';

/// Overridden for development with
/// `--dart-define=COMMUTERLVIV_BASE=http://10.0.2.2:8099`, the host machine as
/// the Android emulator sees it.
const defaultBase = String.fromEnvironment(
  'COMMUTERLVIV_BASE',
  defaultValue: 'https://commuterlviv.r1a.nl',
);

class ApiError implements Exception {
  ApiError(this.message, this.status);

  final String message;
  final int status;

  bool get unauthorised => status == 401;

  @override
  String toString() => message;
}

class Api {
  Api._(this._prefs, this._base, this._cookies);

  static const _baseKey = 'commuterlviv.base';
  static const _jarKey = 'commuterlviv.cookies';
  static const _catalogKey = 'commuterlviv.catalog';
  static const _shapesKey = 'commuterlviv.shapes';

  /// The jar is a credential, so it lives in the Keystore rather than in prefs.
  static const _safe = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<Api> open() async {
    final prefs = await SharedPreferences.getInstance();
    final stale = prefs.getString(_jarKey);
    if (stale != null) {
      await _safe.write(key: _jarKey, value: stale);
      await prefs.remove(_jarKey);
    }
    final jar = await _safe.read(key: _jarKey);
    return Api._(
      prefs,
      prefs.getString(_baseKey) ?? defaultBase,
      jar == null
          ? <String, String>{}
          : (jsonDecode(jar) as Map<String, dynamic>).cast<String, String>(),
    );
  }

  final SharedPreferences _prefs;
  final HttpClient _http = HttpClient();
  final Map<String, String> _cookies;
  String _base;

  String get base => _base;

  /// Drops everything held for the old server. False when the address did not change.
  Future<bool> setBase(String value) async {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == _base) return false;
    _base = trimmed;
    _cookies.clear();
    await _prefs.setString(_baseKey, trimmed);
    await _safe.delete(key: _jarKey);
    for (final key in [_catalogKey, _shapesKey]) {
      await _prefs.remove(key);
      await _prefs.remove('$key.tag');
    }
    return true;
  }

  Map<String, String> get socketHeaders => {
    'Origin': appOrigin,
    if (_cookies.isNotEmpty) 'Cookie': _cookieHeader,
  };

  Uri socketUri() {
    final u = Uri.parse('$_base/ws');
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws');
  }

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Secure cookies come back prefixed `__Host-`, so match both names.
  String get _csrf {
    for (final e in _cookies.entries) {
      if (e.key == 'lp_csrf' || e.key == '__Host-lp_csrf') return e.value;
    }
    return '';
  }

  Future<void> _take(HttpClientResponse res) async {
    var touched = false;
    for (final c in res.cookies) {
      // A deletion arrives as the same cookie with an empty value and a past
      // expiry; storing it would resurrect a dead session
      if (c.value.isEmpty || (c.maxAge != null && c.maxAge! <= 0)) {
        touched |= _cookies.remove(c.name) != null;
      } else {
        _cookies[c.name] = c.value;
        touched = true;
      }
    }
    if (touched) await _safe.write(key: _jarKey, value: jsonEncode(_cookies));
  }

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final req = await _http.openUrl(method, Uri.parse('$_base$path'));
    req.headers.set('Origin', appOrigin);
    if (_cookies.isNotEmpty) req.headers.set('Cookie', _cookieHeader);
    if (method != 'GET') req.headers.set('X-CSRF-Token', _csrf);
    headers.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    await _take(res);
    return res;
  }

  Future<dynamic> _call(String method, String path, {Object? body}) async {
    final res = await _send(method, path, body: body);
    final text = await res.transform(utf8.decoder).join();
    final data = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 400) {
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : 'the server said ${res.statusCode}';
      throw ApiError(message, res.statusCode);
    }
    return data;
  }

  Future<Me> me() async =>
      Me.fromJson(await _call('GET', '/api/me') as Map<String, dynamic>);

  Future<void> login(String username, String password, bool remember) => _call(
    'POST',
    '/api/login',
    body: {'username': username, 'password': password, 'remember': remember},
  );

  /// An empty code posts to the codeless route, which only an `open` server accepts.
  Future<void> register(
    String code,
    String username,
    String password,
    bool remember,
  ) => _call(
    'POST',
    code.isEmpty
        ? '/api/register'
        : '/api/register/${Uri.encodeComponent(code)}',
    body: {'username': username, 'password': password, 'remember': remember},
  );

  /// Registration mode: `open`, `code` or `closed`. Also settles the tile
  /// origin, so it must run before the map builds.
  Future<String> health() async {
    final h = await _call('GET', '/api/health') as Map<String, dynamic>;
    setTileOrigin(h['tiles'] == true ? '$_base/tiles' : null);
    return h['registration'] as String? ?? 'code';
  }

  Future<void> logout() => _call('POST', '/api/logout');

  Future<Sets> sets() async =>
      Sets.fromJson(await _call('GET', '/api/sets') as Map<String, dynamic>);

  Future<RouteSet> createSet(String name, List<String> routes) async =>
      RouteSet.fromJson(
        await _call('POST', '/api/sets', body: {'name': name, 'routes': routes})
            as Map<String, dynamic>,
      );

  Future<RouteSet> updateSet(
    String id,
    String name,
    List<String> routes,
  ) async => RouteSet.fromJson(
    await _call('PUT', '/api/sets/$id', body: {'name': name, 'routes': routes})
        as Map<String, dynamic>,
  );

  Future<void> deleteSet(String id) => _call('DELETE', '/api/sets/$id');

  Future<void> activateSet(String? id) =>
      _call('POST', '/api/sets/active', body: {'id': id});

  Future<List<Call>> vehicle(int veh) async {
    final answer =
        await _call('GET', '/api/vehicle?veh=$veh') as Map<String, dynamic>;
    return [
      for (final c in answer['stops'] as List)
        Call.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// Door to door, ranked by arrival. Near a second on the server, so ask once
  /// per search.
  Future<List<Journey>> plan(LatLng from, LatLng to) async {
    final answer = await _call(
      'GET',
      '/api/plan?from=${from.latitude},${from.longitude}'
          '&to=${to.latitude},${to.longitude}',
    ) as Map<String, dynamic>;
    return [
      for (final j in answer['options'] as List)
        Journey.fromJson(j as Map<String, dynamic>),
    ];
  }

  Future<Catalog> catalog() async => Catalog.fromJson(
    await _held('/api/catalog', _catalogKey, what: 'the catalog'),
  );

  /// Half a megabyte of route geometry, so asked for only when a line is drawn.
  Future<Shapes> shapes() async => Shapes.fromJson(
    await _held('/api/shapes', _shapesKey, what: 'the route lines'),
  );

  /// Cached on disk under [key], with its ETag under `key.tag`.
  Future<Map<String, dynamic>> _held(
    String path,
    String key, {
    required String what,
  }) async {
    final tag = _prefs.getString('$key.tag');
    final held = _prefs.getString(key);
    final res = await _send(
      'GET',
      path,
      headers: {if (tag != null && held != null) 'If-None-Match': tag},
    );
    if (res.statusCode == 304 && held != null) {
      await res.drain<void>();
      return jsonDecode(held) as Map<String, dynamic>;
    }
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw ApiError(
        '$what would not load (${res.statusCode})',
        res.statusCode,
      );
    }
    final fresh = res.headers.value('etag');
    if (fresh != null) {
      await _prefs.setString(key, text);
      await _prefs.setString('$key.tag', fresh);
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  String? get mapTheme => _prefs.getString('commuterlviv.theme');

  Future<void> setMapTheme(String id) =>
      _prefs.setString('commuterlviv.theme', id);

  /// Null means the phone's own, which is what `main` falls back to.
  String? get language => _prefs.getString('commuterlviv.lang');

  Future<void> setLanguage(String code) =>
      _prefs.setString('commuterlviv.lang', code);

  /// Pinned stops, by feed id, kept server-side so phone and browser agree.
  Future<List<String>> pins() async {
    final j = await _call('GET', '/api/pins') as Map<String, dynamic>;
    return [for (final p in j['pins'] as List) p as String];
  }

  Future<void> setPins(List<String> stops) =>
      _call('POST', '/api/pins', body: {'pins': stops});

  Future<List<Place>> setPlaces(List<Place> places) async {
    final j =
        await _call(
              'POST',
              '/api/places',
              body: {'places': [for (final p in places) p.toJson()]},
            )
            as Map<String, dynamic>;
    return [
      for (final p in j['places'] as List)
        Place.fromJson(p as Map<String, dynamic>),
    ];
  }

  /// Pins from before the server kept them, as catalog positions. Read once
  /// per account, then forgotten.
  List<int>? oldPins(String user) {
    final raw = _prefs.getStringList('commuterlviv.pins.$user');
    return raw == null ? null : [for (final s in raw) int.parse(s)];
  }

  Future<void> forgetOldPins(String user) =>
      _prefs.remove('commuterlviv.pins.$user');
}
