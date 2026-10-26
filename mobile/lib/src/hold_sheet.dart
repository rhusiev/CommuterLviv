/// What a long press on the map offers for the point held: keeping it under a
/// name, the way there or from there, and the stops around it.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'point_label.dart';
import 'strings.dart';

class HoldSheet extends StatefulWidget {
  const HoldSheet({
    super.key,
    required this.at,
    required this.catalog,
    required this.onSave,
    required this.onTo,
    required this.onFrom,
    required this.onNear,
  });

  final LatLng at;

  /// The stops [at] may be named by
  final Catalog catalog;
  final void Function(String name) onSave;
  final VoidCallback onTo;
  final VoidCallback onFrom;
  final VoidCallback onNear;

  @override
  State<HoldSheet> createState() => _HoldSheetState();
}

/// Owns the name field, so it is disposed with the sheet.
class _HoldSheetState extends State<HoldSheet> {
  final _name = TextEditingController();
  bool _naming = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isNotEmpty) widget.onSave(name);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Above the keyboard while the name is typed
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                txt.thisPlace,
                style: material.Theme.of(context).textTheme.titleLarge,
              ),
              subtitle: Text(pointLabel(widget.catalog, widget.at)),
            ),
            if (_naming) _nameField() else ..._actions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions() => [
    ListTile(
      leading: const Icon(Icons.star_border),
      title: Text(txt.savePlaceAs),
      onTap: () => setState(() => _naming = true),
    ),
    ListTile(
      leading: const Icon(Icons.directions),
      title: Text(txt.toHere),
      onTap: widget.onTo,
    ),
    ListTile(
      leading: const Icon(Icons.trip_origin),
      title: Text(txt.fromHere),
      onTap: widget.onFrom,
    ),
    ListTile(
      leading: const Icon(Icons.directions_bus_outlined),
      title: Text(txt.nearHere),
      onTap: widget.onNear,
    ),
  ];

  Widget _nameField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Column(
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(labelText: txt.namePlace),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(txt.cancel),
            ),
            ListenableBuilder(
              listenable: _name,
              builder: (context, _) => FilledButton(
                onPressed: _name.text.trim().isEmpty ? null : _save,
                child: Text(txt.saveHere),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
