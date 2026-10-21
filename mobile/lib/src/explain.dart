/// A word that explains itself when tapped, marked by an ⓘ.
library;

import 'package:flutter/material.dart';

/// The size of the ⓘ beside a word that explains itself
const infoIconSize = 14.0;

/// Says [why] about [title], until it is dismissed
Future<void> explain(BuildContext context, String title, String why) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(title),
        content: Text(why),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
