/// Talking to `commuterlviv serve`.
///
/// The service was written for a browser, so it authenticates with cookies and
/// guards every unsafe request with a double-submitted CSRF token and an Origin
/// check. An app is not a browser and gets none of that for free, so this class
/// is the small amount of browser the app has to be: a cookie jar, an `Origin`
/// header, and the CSRF cookie echoed back as a header. Nothing on the server
/// changes for the app - except that `app://commuterlviv` has to be listed in
/// `COMMUTERLVIV_ORIGINS`, which is a deployment setting, not code.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'map_theme.dart';
import 'models.dart';

/// The value the server checks against `COMMUTERLVIV_ORIGINS`. A scheme no browser
/// will ever mint, so listing it cannot widen what a web page may do.
const appOrigin = 'app://commuterlviv';

/// Where to talk to, unless the sign-in screen was given something else. The
/// default is the deployment this app is published for; an F-Droid build passes
/// nothing, so it has to be the real one. Development overrides it with
/// `--dart-define=COMMUTERLVIV_BASE=http://10.0.2.2:8099`, which is the host machine
/// as the Android emulator sees it.
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
  static const _catalogTagKey = 'commuterlviv.catalog.tag';

  /// The jar and nothing else. Everything else this class stores is a
  /// preference; the jar is a credential, so it lives in the Keystore.
  static const _safe = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<Api> open() async {
    final prefs = await SharedPreferences.getInstance();
    // A build before 0.3.2 kept the jar in plain preferences. Moving it rather
    // than dropping it means an upgrade does not sign everyone out
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

  /// Everything held for the old server goes with it - the session it issued is
  /// meaningless anywhere else. False when the address did not change
  Future<bool> setBase(String value) async {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == _base) return false;
    _base = trimmed;
    _cookies.clear();
    await _prefs.setString(_baseKey, trimmed);
    await _safe.delete(key: _jarKey);
    await _prefs.remove(_catalogKey);
    await _prefs.remove(_catalogTagKey);
    return true;
  }

  /// The socket needs the same cookies and the same origin as everything else,
  /// and it is opened by `Live`, which has no business knowing about the jar.
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

  /// The service prefixes cookie names with `__Host-` when it sets secure
  /// cookies, so the token is found by suffix rather than by exact name
  String get _csrf {
    for (final e in _cookies.entries) {
      if (e.key == 'lp_csrf' || e.key == '__Host-lp_csrf') return e.value;
    }
    return '';
  }

  Future<void> _take(HttpClientResponse res) async {
    var touched = false;
    for (final c in res.cookies) {
      // A deletion arrives as the same cookie with an empty value and an
      // expiry in the past; treating it as a value would resurrect a dead
      // session on the next request
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

  /// An empty code posts to the codeless route, which only a server whose
  /// registration is `open` accepts
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

  /// `open`, `code` or `closed` - which of the three ways in the sign-in screen
  /// should offer. Public, because nobody is signed in when it is asked.
  ///
  /// Asking also settles where the basemap comes from: a server that serves its
  /// own says so, and it serves it at `/tiles` under the address this app was
  /// pointed at. That is why the app carries no tile host of its own - point it
  /// at another deployment and it follows that one's map too.
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

  /// Where one vehicle is going, and when it gets there: the predictions the
  /// socket already sends per stop, asked the other way round
  Future<List<Call>> vehicle(int veh) async {
    final answer =
        await _call('GET', '/api/vehicle?veh=$veh') as Map<String, dynamic>;
    return [
      for (final c in answer['stops'] as List)
        Call.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// Door to door: walk to a stop, ride, walk to the door, ranked by arrival.
  /// Most of a second at the far end, so it is asked once per search
  Future<List<Journey>> plan(LatLng from, LatLng to) async {
    final answer =
        await _call(
              'GET',
              '/api/plan?from=${from.latitude},${from.longitude}'
              '&to=${to.latitude},${to.longitude}',
            )
            as Map<String, dynamic>;
    return [
      for (final j in answer['options'] as List)
        Journey.fromJson(j as Map<String, dynamic>),
    ];
  }

  /// The catalog is a megabyte of names that never change while the service is
  /// up, so it is kept on disk against the tag the service sends and the usual
  /// request is a 304 with no body.
  Future<Catalog> catalog() async {
    final tag = _prefs.getString(_catalogTagKey);
    final held = _prefs.getString(_catalogKey);
    final res = await _send(
      'GET',
      '/api/catalog',
      headers: {if (tag != null && held != null) 'If-None-Match': tag},
    );
    if (res.statusCode == 304 && held != null) {
      await res.drain<void>();
      return Catalog.fromJson(jsonDecode(held) as Map<String, dynamic>);
    }
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw ApiError(
        'the catalog would not load (${res.statusCode})',
        res.statusCode,
      );
    }
    final fresh = res.headers.value('etag');
    if (fresh != null) {
      await _prefs.setString(_catalogKey, text);
      await _prefs.setString(_catalogTagKey, fresh);
    }
    return Catalog.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  /// The basemap style is a device thing too, and one the app should come back
  /// wearing rather than reset to the default on every launch
  String? get mapTheme => _prefs.getString('commuterlviv.theme');

  Future<void> setMapTheme(String id) =>
      _prefs.setString('commuterlviv.theme', id);

  /// The language, if one was ever chosen here. Null means the phone's own,
  /// which is what `main` falls back to
  String? get language => _prefs.getString('commuterlviv.lang');

  Future<void> setLanguage(String code) =>
      _prefs.setString('commuterlviv.lang', code);

  /// Pinned stops, kept by the server so the phone and the browser agree, and
  /// held by feed id for the same reason route sets are.
  Future<List<String>> pins() async {
    final j = await _call('GET', '/api/pins') as Map<String, dynamic>;
    return [for (final p in j['pins'] as List) p as String];
  }

  Future<void> setPins(List<String> stops) =>
      _call('POST', '/api/pins', body: {'pins': stops});

  /// What this device pinned before the server kept pins, as catalog positions
  /// - the bug that moved them. Read once per account and then forgotten.
  List<int>? oldPins(String user) {
    final raw = _prefs.getStringList('commuterlviv.pins.$user');
    return raw == null ? null : [for (final s in raw) int.parse(s)];
  }

  Future<void> forgetOldPins(String user) =>
      _prefs.remove('commuterlviv.pins.$user');
}
