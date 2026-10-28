// No widget test may share this file: the widget binding refuses real HTTP,
// and these tests talk to a socket on loopback.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/live.dart';

const _patience = Duration(seconds: 5);

/// How long a vehicle slides to a new report, as `live.dart` eases it.
const _easeMs = 1200;

/// Completes once [met] holds after a change [live] announces.
Future<void> _until(Live live, bool Function() met) {
  final done = Completer<void>();
  void check() {
    if (met() && !done.isCompleted) done.complete();
  }

  live.addListener(check);
  return done.future
      .timeout(_patience)
      .whenComplete(() => live.removeListener(check));
}

void main() {
  late HttpServer server;
  late StreamIterator<WebSocket> sockets;
  late Live live;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sockets = StreamIterator(server.transform(WebSocketTransformer()));
    final api = await Api.open();
    await api.setBase('http://${server.address.host}:${server.port}');
    live = Live(api, onRenewed: () {})..open();
  });

  tearDown(() async {
    live.dispose();
    await server.close(force: true);
  });

  Future<WebSocket> accepted() async {
    expect(await sockets.moveNext().timeout(_patience), isTrue);
    return sockets.current;
  }

  test('the vehicles going quiet is taken from the hello, '
      'then from each change the service sends', () async {
    final ws = await accepted();

    ws.add(jsonEncode({'type': 'hello', 'quiet': true}));
    await _until(live, () => live.quiet);
    ws.add(jsonEncode({'type': 'quiet', 'quiet': false}));
    await _until(live, () => !live.quiet);
  });

  test(
    'the vehicles going quiet is not known once the socket is down',
    () async {
      final ws = await accepted();
      ws.add(jsonEncode({'type': 'hello', 'quiet': true}));
      await _until(live, () => live.quiet);

      await ws.close();

      await _until(live, () => live.connection != Connection.live);
      expect(live.quiet, isFalse);
    },
  );

  test('a position frame says so, and asks for drawing as long as the '
      'slide it starts', () async {
    final ws = await accepted();
    final bytes =
        (jsonDecode(File('../tests/wire_frame.json').readAsStringSync())
                as Map<String, dynamic>)['bytes']
            as List<dynamic>;
    final moved = Completer<void>();
    live.moves.addListener(() {
      if (!moved.isCompleted) moved.complete();
    });
    final before = live.nowMs;

    ws.add(bytes.cast<int>());
    await moved.future.timeout(_patience);

    expect(live.easingUntil, greaterThanOrEqualTo(before + _easeMs));
    expect(live.easingUntil, lessThanOrEqualTo(live.nowMs + _easeMs));
  });
}
