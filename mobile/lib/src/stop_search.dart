/// Stops by name. The catalog is a thousand stops, which is small enough to
/// scan on every keystroke and not worth an index.
library;

import 'package:flutter/material.dart';

import 'models.dart';
import 'strings.dart';

class StopSearch extends SearchDelegate<int?> {
  StopSearch(this.catalog) : super(searchFieldLabel: txt.findStop);

  final Catalog catalog;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const BackButtonIcon(),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const SizedBox.shrink();
    final hits = [
      for (var i = 0; i < catalog.stops.length; i++)
        if (catalog.stops[i].name.toLowerCase().contains(needle)) i,
    ];
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, k) {
        final s = catalog.stops[hits[k]];
        return ListTile(
          title: Text(s.name),
          subtitle: Text(
            [for (final r in s.routes) catalog.routes[r].short].join(' · '),
          ),
          onTap: () => close(context, hits[k]),
        );
      },
    );
  }
}
