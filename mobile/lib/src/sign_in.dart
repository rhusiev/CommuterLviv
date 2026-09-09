/// Signing in, and taking up an invite.
///
/// One form, and what it offers is the server's `COMMUTERLVIV_REGISTRATION`, read
/// from `/api/health` before anyone is signed in: an invite field, a sign-up
/// button, or neither. The server address is editable here as well as from the
/// menu, because someone who has never signed in has no menu to reach.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;

import 'api.dart';
import 'server_dialog.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.api, required this.onIn});

  final Api api;
  final void Function(String username) onIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _joining = false;
  bool _remember = true;
  bool _busy = false;
  String? _error;

  /// Until the server has answered, assume the strictest way in that still
  /// works: an invite code is what every deployment accepts
  String _mode = 'code';

  @override
  void initState() {
    super.initState();
    _askMode();
  }

  Future<void> _askMode() async {
    try {
      final mode = await widget.api.registration();
      if (mounted) {
        setState(() {
          _mode = mode;
          if (mode == 'closed') _joining = false;
        });
      }
    } on Exception {
      // A server that cannot be reached is a problem for _submit to report
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _username.text.trim();
      if (_joining) {
        await widget.api.register(
          _code.text.trim(),
          name,
          _password.text,
          _remember,
        );
      } else {
        await widget.api.login(name, _password.text, _remember);
      }
      // Ends the autofill session, which is what makes the manager offer to
      // save what was just typed - it never sees the form leave the screen
      TextInput.finishAutofillContext();
      widget.onIn(name);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } on Exception {
      setState(() => _error = 'could not reach ${widget.api.base}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editServer() async {
    if (await editServer(context, widget.api) && mounted) {
      setState(() {
        _mode = 'code';
        _joining = false;
      });
      await _askMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              // The group is what a password manager sees: without it Android is
              // offered two unrelated fields and Bitwarden will not fill either
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('CommuterLviv', style: text.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'where the buses actually are',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    if (_joining && _mode == 'code') ...[
                      TextField(
                        controller: _code,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Invite code',
                          helperText: 'the last part of the link you were sent',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _username,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      onSubmitted: (_) => _busy ? null : _submit(),
                      autofillHints: [
                        _joining
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile.adaptive(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v),
                      title: const Text('Stay signed in'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator.adaptive(),
                            )
                          : Text(
                              _joining
                                  ? (_mode == 'open'
                                        ? 'Create the account'
                                        : 'Join')
                                  : 'Sign in',
                            ),
                    ),
                    if (_mode != 'closed')
                      TextButton(
                        onPressed: () => setState(() => _joining = !_joining),
                        child: Text(
                          _joining
                              ? 'I already have an account'
                              : (_mode == 'open'
                                    ? 'Create an account'
                                    : 'I have an invite code'),
                        ),
                      ),
                    TextButton(
                      onPressed: _editServer,
                      child: Text(widget.api.base),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
