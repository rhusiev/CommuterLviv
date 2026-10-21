/// A place picked by name, from the bottom of the map: what it is, whether it
/// is kept, and the way there.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'strings.dart';

class PlaceCard extends StatefulWidget {
  const PlaceCard({
    super.key,
    required this.name,
    this.where = '',
    required this.saved,
    required this.onSave,
    required this.onGo,
  });

  final String name;

  /// The line under a place found by name
  final String where;

  /// Only the initial state: the screen behind cannot rebuild a sheet, so the
  /// card tracks its own save from here.
  final bool saved;

  final VoidCallback onSave;
  final VoidCallback onGo;

  @override
  State<PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<PlaceCard> {
  late bool _saved = widget.saved;

  @override
  Widget build(BuildContext context) {
    final under = _saved ? txt.saved : widget.where;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.name,
                    style: material.Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                // As in the search: a saved place's star only says so
                if (_saved)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.star),
                  )
                else
                  IconButton(
                    onPressed: () {
                      setState(() => _saved = true);
                      widget.onSave();
                    },
                    icon: const Icon(Icons.star_border),
                    tooltip: txt.savePlace,
                  ),
              ],
            ),
            if (under.isNotEmpty) Text(under),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: widget.onGo,
              icon: const Icon(Icons.place_outlined),
              label: Text(txt.getHere),
            ),
          ],
        ),
      ),
    );
  }
}
