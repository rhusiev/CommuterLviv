/// Asking which server to talk to, from the sign-in screen and from the menu.
library;

import 'package:flutter/material.dart';

import 'api.dart';
import 'strings.dart';

/// True when the address changed, which also drops the stored session and
/// catalog.
Future<bool> editServer(BuildContext context, Api api) async {
  final value = await showDialog<String>(
    context: context,
    builder: (context) => _ServerDialog(api.base),
  );
  if (value == null || value.trim().isEmpty) return false;
  return api.setBase(value);
}

/// Owns its field, so the field outlives the dialog's closing animation.
class _ServerDialog extends StatefulWidget {
  const _ServerDialog(this.base);

  final String base;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _field = TextEditingController(text: widget.base);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(txt.server),
    content: TextField(
      controller: _field,
      autocorrect: false,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(hintText: 'https://lviv.example.org'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(txt.cancel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _field.text),
        child: Text(txt.use),
      ),
    ],
  );
}
