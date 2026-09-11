/// Asking which server to talk to, from the sign-in screen and from the menu.
library;

import 'package:flutter/material.dart';

import 'api.dart';
import 'strings.dart';

/// True when the address changed, which also drops the stored session and
/// catalog.
Future<bool> editServer(BuildContext context, Api api) async {
  final field = TextEditingController(text: api.base);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(txt.server),
      content: TextField(
        controller: field,
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
          onPressed: () => Navigator.pop(context, field.text),
          child: Text(txt.use),
        ),
      ],
    ),
  );
  field.dispose();
  if (value == null || value.trim().isEmpty) return false;
  return api.setBase(value);
}
