/// The other ways to the door from where each ride of a journey boards.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'end_field.dart';
import 'eta.dart';
import 'models.dart';
import 'route_badge.dart';
import 'strings.dart';

/// The [n]-th backup of a journey's [leg]-th leg; null stands for the journey.
typedef WayPick = ({int leg, int n});

/// Per ride, the planned way to the door from where it boards and then the
/// shortlist of other ways by [prefer], until all are asked for. A tap on one
/// draws it with [onWay], closing unless that answers what went wrong. A way
/// that
/// is also an option of the plan says which, numbered by [place] from its
/// index in the plan.
Future<void> showBackups(
  BuildContext context, {
  required Journey journey,
  required Prefer prefer,
  required Catalog catalog,
  required int Function(int option) place,
  required Future<String?> Function(WayPick? pick) onWay,
}) => showDialog<void>(
  context: context,
  builder: (_) => _Backups(
    journey: journey,
    prefer: prefer,
    catalog: catalog,
    place: place,
    onWay: onWay,
  ),
);

class _Backups extends StatefulWidget {
  const _Backups({
    required this.journey,
    required this.prefer,
    required this.catalog,
    required this.place,
    required this.onWay,
  });

  final Journey journey;
  final Prefer prefer;
  final Catalog catalog;
  final int Function(int option) place;
  final Future<String?> Function(WayPick? pick) onWay;

  @override
  State<_Backups> createState() => _BackupsState();
}

class _BackupsState extends State<_Backups> {
  bool _pending = false;
  String? _failed;

  Future<void> _pick(WayPick? which) async {
    setState(() {
      _pending = true;
      _failed = null;
    });
    final failed = await widget.onWay(which);
    if (!mounted) return;
    if (failed == null) return Navigator.pop(context);
    setState(() {
      _pending = false;
      _failed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final catalog = widget.catalog;
    final theme = material.Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final rides = [
      for (final leg in journey.legs)
        if (!leg.walking) leg,
    ];
    Widget way(
      List<Leg> chain,
      int arr,
      WayPick? which, {
      List<bool> planned = const [],
      int option = -1,
    }) => Tooltip(
      message: txt.showWay,
      child: InkWell(
        onTap: _pending ? null : () => _pick(which),
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          padding: const EdgeInsets.all(4),
          decoration: which == null
              ? BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Opacity(
            opacity: _pending ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(clockTime(chain.first.dep)),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final (i, r) in chain.indexed) ...[
                            if (i > 0)
                              const Icon(Icons.chevron_right, size: 16),
                            RouteBadge(
                              route: catalog.routes[r.route!],
                              fontSize: 11,
                              outline: planned.elementAtOrNull(i) ?? false,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (option >= 0)
                      Tooltip(
                        message: txt.alsoOptionHint,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            txt.alsoOption(widget.place(option)),
                            style: small?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    Icon(endIcon(End.to), size: 14),
                    Text(clockTime(arr)),
                  ],
                ),
                if (chain.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 44, top: 2),
                    child: Text(
                      txt.changeAt(
                        chain
                            .skip(1)
                            .map((r) => catalog.stops[r.a].name)
                            .join(', '),
                      ),
                      style: small,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return AlertDialog(
      title: Text(txt.backups),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(txt.backupsWhy, style: small),
          if (_failed case final failed?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                failed,
                style: small?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          for (final (i, leg) in rides.indexed) ...[
            const Divider(height: 20),
            Text(catalog.stops[leg.a].name, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            way(rides.sublist(i), journey.arr, null),
            if (leg.backups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(txt.noBackup, style: small),
              )
            else
              _Ways(
                backups: leg.backups,
                prefer: widget.prefer,
                way: (b) => way(
                  b.rides,
                  b.arr,
                  (leg: journey.legs.indexOf(leg), n: leg.backups.indexOf(b)),
                  planned: b.planned,
                  option: b.option,
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// A ride's backups, the shortlist by what is preferred until asked for all.
class _Ways extends StatefulWidget {
  const _Ways({required this.backups, required this.prefer, required this.way});

  final List<Backup> backups;
  final Prefer prefer;
  final Widget Function(Backup b) way;

  @override
  State<_Ways> createState() => _WaysState();
}

class _WaysState extends State<_Ways> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final shown = _all
        ? widget.backups
        : widget.prefer.shortlist(widget.backups);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in shown) widget.way(b),
        if (shown.length < widget.backups.length)
          TextButton(
            onPressed: () => setState(() => _all = true),
            child: Text(txt.moreBackups(widget.backups.length - shown.length)),
          ),
      ],
    );
  }
}
