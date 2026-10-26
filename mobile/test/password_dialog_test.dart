import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/password_dialog.dart';
import 'package:commuterlviv/src/strings.dart';

const _old = 'a long enough password';
const _next = 'another long password';
const _refused = 'The current password is wrong';
const _unreachable = 'nobody answered';

/// Opens the dialog over a page, and keeps what it closed with.
Future<List<bool?>> _open(
  WidgetTester tester,
  Future<void> Function(String old, String next) change,
) async {
  final closed = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => closed.add(
            await showDialog<bool>(
              context: context,
              builder: (_) =>
                  PasswordDialog(change: change, unreachable: _unreachable),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, _old);
  await tester.enterText(find.byType(TextField).last, _next);
  return closed;
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, txt.changePassword));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the passwords typed are sent, and the dialog closes taken', (
    tester,
  ) async {
    final sent = <List<String>>[];
    final closed = await _open(tester, (old, next) async {
      sent.add([old, next]);
    });

    await _submit(tester);

    expect(sent, [
      [_old, _next],
    ]);
    expect(closed, [true]);
  });

  testWidgets('a refusal stays up and says why', (tester) async {
    final closed = await _open(tester, (_, _) async {
      throw ApiError(_refused, 400);
    });

    await _submit(tester);

    expect(find.text(_refused), findsOneWidget);
    expect(closed, isEmpty);
  });

  testWidgets('a service that does not answer is said to', (tester) async {
    final closed = await _open(tester, (_, _) async {
      throw const _NoAnswer();
    });

    await _submit(tester);

    expect(find.text(_unreachable), findsOneWidget);
    expect(closed, isEmpty);
  });

  testWidgets('a change under way cannot be cancelled or backed out of', (
    tester,
  ) async {
    final answer = Completer<void>();
    final closed = await _open(tester, (_, _) => answer.future);
    await tester.tap(find.widgetWithText(TextButton, txt.changePassword));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, txt.cancel));
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(PasswordDialog), findsOneWidget);
    answer.complete();
    await tester.pumpAndSettle();
    expect(closed, [true]);
  });
}

class _NoAnswer implements Exception {
  const _NoAnswer();
}
