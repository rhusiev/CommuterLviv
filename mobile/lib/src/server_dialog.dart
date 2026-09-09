/// Asking which server to talk to.
///
/// There is no one address: the build carries a default, whoever runs a service
/// points the app at theirs. The question is asked from the sign-in screen and
/// again from the menu, so it is written once here.
library;

import 'package:flutter/material.dart';

import 'api.dart';

/// Returns true when the address actually changed - which also means the stored
/// session and catalogue were dropped, because they belonged to the old server
Future<bool> editServer(BuildContext context, Api api) async {
  final field = TextEditingController(text: api.base);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: const Text('Server'),
      content: TextField(
        controller: field,
        autocorrect: false,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(hintText: 'https://lviv.example.org'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, field.text),
          child: const Text('Use'),
        ),
      ],
    ),
  );
  field.dispose();
  if (value == null || value.trim().isEmpty) return false;
  return api.setBase(value);
}
