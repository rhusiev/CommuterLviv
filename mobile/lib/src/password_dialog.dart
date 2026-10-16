/// Changing the password, from the account sheet.
library;

import 'package:flutter/material.dart';

import 'api.dart';
import 'strings.dart';

/// True once [Api.password] took the new password.
Future<bool> changePassword(BuildContext context, Api api) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => PasswordDialog(
        change: api.password,
        unreachable: txt.unreachable(api.base),
      ),
    ) ??
    false;

/// Stays up while the service refuses, saying why, and closes with true once
/// it takes the new password.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({
    super.key,
    required this.change,
    required this.unreachable,
  });

  final Future<void> Function(String old, String next) change;

  /// Said when the service did not answer at all.
  final String unreachable;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _old = TextEditingController();
  final _next = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.change(_old.text, _next.text);
      if (mounted) Navigator.pop(context, true);
      return;
    } on ApiError catch (e) {
      _error = e.message;
    } on Exception {
      _error = widget.unreachable;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(txt.changePassword),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _old,
          obscureText: true,
          autofocus: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(labelText: txt.currentPassword),
        ),
        TextField(
          controller: _next,
          obscureText: true,
          onSubmitted: (_) => _busy ? null : _submit(),
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: txt.newPassword,
            helperText: txt.passwordHint,
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(txt.cancel),
      ),
      TextButton(
        onPressed: _busy ? null : _submit,
        child: Text(txt.changePassword),
      ),
    ],
  );
}
