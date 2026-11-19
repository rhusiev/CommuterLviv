import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/strings.dart';

void main() {
  late Api api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    api = await Api.open();
  });

  test('a refusal is told in the server\'s own words', () {
    expect(api.failure(ApiError('too many places', 400)), 'too many places');
  });

  test('the route refresh is off until asked, and kept once asked', () async {
    expect(api.routeRefresh, isFalse);

    await api.setRouteRefresh(true);
    expect(api.routeRefresh, isTrue);

    await api.setRouteRefresh(false);
    expect(api.routeRefresh, isFalse);
  });

  test('a server that did not answer is told as unreachable', () {
    expect(
      api.failure(const SocketException('refused')),
      txt.unreachable(api.base),
    );
  });
}
