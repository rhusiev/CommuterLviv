/// Door to door: two points, and the ways between them. A ride not resting on a
/// tracked vehicle says so, and why that matters.
library;

export 'end_field.dart' show End;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'backups_dialog.dart';
import 'end_field.dart';
import 'eta.dart';
import 'follow.dart' show followable;
import 'models.dart';
import 'route_badge.dart';
import 'sheets.dart';
import 'strings.dart';
import 'theme.dart';
import 'walk_speed.dart';

/// A word on a ride not resting on a tracked vehicle, and what it means; null
/// on one that is.
(String, String)? legNote(Confidence confidence) => switch (confidence) {
  Confidence.live => null,
  Confidence.terminus => (txt.terminusPart, txt.terminusWhy),
  Confidence.schedule => (txt.schedulePart, txt.scheduleWhy),
  Confidence.quiet => (txt.quietPart, txt.quietWhy),
};

class JourneyPanel extends StatefulWidget {
  const JourneyPanel({
    super.key,
    required this.api,
    required this.catalog,
    required this.from,
    required this.to,
    required this.picking,
    required this.onPick,
    required this.folded,
    required this.onFold,
    required this.onSwap,
    required this.onHere,
    required this.onStop,
    required this.onLine,
    required this.places,
    required this.onSave,
    required this.onPlace,
    required this.onShow,
    required this.onFollow,
  });

  final Api api;
  final Catalog catalog;
  final LatLng? from;
  final LatLng? to;

  /// The end waiting on a tap on the map; the panel folds out of its way
  final End? picking;
  final void Function(End? which) onPick;

  /// Folded down to a strip, the map and the option on it in view
  final bool folded;
  final void Function(bool folded) onFold;
  final VoidCallback onSwap;
  final void Function(End which) onHere;
  final void Function(int stop) onStop;

  final void Function(int route) onLine;

  final List<Place> places;
  final void Function(String name, LatLng at) onSave;
  final void Function(End end, LatLng at) onPlace;

  /// The option picked to be drawn on the map, or null once none is
  final void Function(Journey? journey) onShow;
  final void Function(Journey journey) onFollow;

  @override
  State<JourneyPanel> createState() => _JourneyPanelState();
}

class _JourneyPanelState extends State<JourneyPanel> {
  List<Journey>? _options;
  Journey? _shown;
  bool _busy = false;
  String? _failed;

  /// The id to report the options shown by, and what came of reporting them
  String? _report;
  String? _reportSaid;

  /// The search's name for its backups, which reporting it leaves alone; the
  /// backups fetched as options of their own, by the option, leg and backup
  /// they came from; and the option of the search's each was built from
  ({String? id, Map<String, Journey> built, Map<Journey, int> from}) _held = (
    id: null,
    built: {},
    from: {},
  );

  /// What the points picked by name were called, so they keep reading so
  final _names = <LatLng, String>{};

  /// Unix seconds to leave at; null is now, which is what the server assumes.
  int? _at;

  late Prefer _prefer = widget.api.prefer;

  /// km/h on the level, starting from the one kept as the usual.
  late double _speed = widget.api.walkSpeed;

  @override
  void didUpdateWidget(JourneyPanel old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from ||
        old.to != widget.to ||
        old.catalog != widget.catalog) {
      _forget();
    }
  }

  void _forget() {
    _options = null;
    _failed = null;
    _report = _reportSaid = null;
    _held = (id: null, built: {}, from: {});
    _show(null);
  }

  void _show(Journey? journey) {
    if (journey == _shown) return;
    _shown = journey;
    widget.onShow(journey);
  }

  /// The last day any time of which the server still plans, 30 days ahead
  static const _lastDay = 29;

  DateTime get _leaving => _at == null
      ? DateTime.now()
      : DateTime.fromMillisecondsSinceEpoch(_at! * 1000);

  void _leave(DateTime? at) => setState(() {
    _at = at == null ? null : at.millisecondsSinceEpoch ~/ 1000;
    _forget();
  });

  /// Keeps the time of day, or leaves now on a day that is today by then.
  Future<void> _pickDay() async {
    final now = DateTime.now();
    final was = _leaving;
    final day = await showDatePicker(
      context: context,
      initialDate: was,
      firstDate: DateUtils.dateOnly(now),
      lastDate: DateUtils.addDaysToDate(now, _lastDay),
    );
    if (day == null) return;
    final at = DateTime(day.year, day.month, day.day, was.hour, was.minute);
    _leave(at.isAfter(now) ? at : null);
  }

  /// A time already past is meant for the next day.
  Future<void> _pickTime() async {
    final was = _leaving;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(was),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    var at = DateTime(was.year, was.month, was.day, picked.hour, picked.minute);
    if (at.isBefore(DateTime.now())) at = at.add(const Duration(days: 1));
    _leave(at);
  }

  String _dayName(DateTime at) {
    final today = DateUtils.dateOnly(DateTime.now());
    return switch (DateUtils.dateOnly(at).difference(today).inDays) {
      0 => txt.today,
      1 => txt.tomorrow,
      _ => txt.shortDay(at),
    };
  }

  Future<void> _search() async {
    final from = widget.from;
    final to = widget.to;
    if (from == null || to == null) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final got = await widget.api.plan(from, to, at: _at, speed: _speed);
      if (!mounted) return;
      setState(() {
        _options = got.options;
        _report = got.report;
        _reportSaid = null;
        _held = (id: got.report, built: {}, from: {});
      });
      _show(null);
    } on ApiError catch (e) {
      if (mounted) {
        setState(
          () => _failed = e.preparing ? txt.plannerPreparing : e.message,
        );
      }
    } on Exception {
      if (mounted) setState(() => _failed = txt.unreachable(widget.api.base));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Draws [pick] of option [j]: the journey itself, the option riding the
  /// same, or else that way fetched and listed as an option of its own.
  /// Answers what went wrong, if anything did.
  Future<String?> _takeWay(Journey j, WayPick? pick) async {
    if (pick == null) return _showNow(j);
    final options = _options ?? const <Journey>[];
    final same = j.legs[pick.leg].backups[pick.n].option;
    if (same >= 0) return _showNow(options[same]);
    final search = _held;
    final from = search.from[j] ?? options.indexOf(j);
    final key = '$from ${pick.leg} ${pick.n}';
    var got = search.built[key];
    if (got == null) {
      final id = search.id;
      if (id == null) return txt.searchAgain;
      try {
        got = await widget.api.backup(id, from, pick.leg, pick.n);
      } on ApiError catch (e) {
        return e.message;
      } on Exception {
        return txt.unreachable(widget.api.base);
      }
      // a search made meanwhile has options of its own
      if (!mounted || !identical(_held.built, search.built)) return null;
      search.built[key] = got;
      search.from[got] = from;
      _options = [...options, got];
    }
    return _showNow(got);
  }

  /// Shows [j], folding the panel out of the way of it on the map.
  String? _showNow(Journey j) {
    setState(() => _show(j));
    widget.onFold(true);
    return null;
  }

  Future<void> _sendReport() async {
    final id = _report!;
    final note = await askName(context, txt.reportNote, action: txt.send);
    if (note == null) return;
    String? failed;
    try {
      await widget.api.reportPlan(id, note);
    } on ApiError catch (e) {
      failed = e.message;
    } on Exception {
      failed = txt.unreachable(widget.api.base);
    }
    if (!mounted || id != _report) return;
    setState(() {
      if (failed == null) _report = null;
      _reportSaid = failed ?? txt.reported;
    });
  }

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    color: panel,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(panelRadius),
      side: const BorderSide(color: hair),
    ),
    clipBehavior: Clip.antiAlias,
    child: switch (widget.picking) {
      final End end => _Picking(end: end, onCancel: () => widget.onPick(null)),
      null when widget.folded => _Folded(
        shown: _shown,
        catalog: widget.catalog,
        onOpen: () => widget.onFold(false),
      ),
      null => _open(context),
    },
  );

  Widget _open(BuildContext context) {
    final ready = widget.from != null && widget.to != null;
    final ranked = _prefer.ranked(_options ?? const []);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                txt.plan,
                style: material.Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: widget.onSwap,
                icon: const Icon(Icons.swap_vert),
                tooltip: txt.swap,
              ),
              IconButton(
                onPressed: () => widget.onFold(true),
                icon: const Icon(Icons.expand_more),
                tooltip: txt.hidePanel,
              ),
            ],
          ),
          for (final end in End.values)
            EndField(
              end: end,
              at: end == End.from ? widget.from : widget.to,
              api: widget.api,
              catalog: widget.catalog,
              onPick: () => widget.onPick(end),
              onHere: () => widget.onHere(end),
              name: _names[end == End.from ? widget.from : widget.to],
              places: widget.places,
              onPlace: (at, name) {
                if (name != null) _names[at] = name;
                widget.onPlace(end, at);
              },
              onSave: widget.onSave,
            ),
          Row(
            children: [
              RowLabel(text: txt.departAt, icon: Icons.schedule),
              Tooltip(
                message: txt.leaveOn,
                child: ActionChip(
                  label: Text(_dayName(_leaving)),
                  onPressed: _pickDay,
                ),
              ),
              const SizedBox(width: 8),
              InputChip(
                label: Text(_at == null ? txt.now : clockTime(_at!)),
                onPressed: _pickTime,
                onDeleted: _at == null ? null : () => _leave(null),
              ),
              const Spacer(),
              PopupMenuButton<Prefer>(
                icon: const Icon(Icons.sort),
                tooltip: '${txt.preferBy}: ${txt.prefer(_prefer)}',
                initialValue: _prefer,
                onSelected: (p) {
                  setState(() => _prefer = p);
                  widget.api.setPrefer(p);
                },
                itemBuilder: (_) => [
                  for (final p in Prefer.values)
                    PopupMenuItem(value: p, child: Text(txt.prefer(p))),
                ],
              ),
            ],
          ),
          Row(
            children: [
              RowLabel(text: txt.walkSpeed, icon: Icons.directions_walk),
              SpeedStepper(
                kmh: _speed,
                onChanged: (v) => setState(() {
                  _speed = v;
                  _forget();
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: ready && !_busy ? _search : null,
              child: Text(_busy ? txt.searching : txt.findRoute),
            ),
          ),
          if (_failed != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _failed!,
                style: TextStyle(
                  color: material.Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          if (_options != null)
            Flexible(
              child: _options!.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(txt.noJourney),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: ranked.length,
                      itemBuilder: (_, i) => _Option(
                        journey: ranked[i],
                        shown: ranked[i] == _shown,
                        onShow: () => setState(
                          () => _show(ranked[i] == _shown ? null : ranked[i]),
                        ),
                        prefer: _prefer,
                        place: (i) => ranked.indexOf(_options![i]) + 1,
                        catalog: widget.catalog,
                        onStop: widget.onStop,
                        onLine: widget.onLine,
                        onWay: (pick) => _takeWay(ranked[i], pick),
                        onFollow: () => widget.onFollow(ranked[i]),
                      ),
                    ),
            )
          else if (!ready && _failed == null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                txt.planHint,
                style: material.Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_options != null && _reportSaid != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _reportSaid!,
                style: material.Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_options != null && _report != null)
            TextButton.icon(
              onPressed: _sendReport,
              icon: const Icon(Icons.flag_outlined),
              label: Text(txt.report),
            ),
        ],
      ),
    );
  }
}

/// The panel while an end waits on a tap on the map.
class _Picking extends StatelessWidget {
  const _Picking({required this.end, required this.onCancel});

  final End end;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
    child: Row(
      children: [
        RowLabel(text: endLabel(end), icon: endIcon(end)),
        Expanded(child: Text('${endLabel(end)}: ${txt.tapMap}')),
        IconButton(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
        ),
      ],
    ),
  );
}

/// The panel folded to a strip: the option on the map, if one is, in brief.
class _Folded extends StatelessWidget {
  const _Folded({
    required this.shown,
    required this.catalog,
    required this.onOpen,
  });

  final Journey? shown;
  final Catalog catalog;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context).textTheme;
    final j = shown;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            if (j == null)
              Expanded(child: Text(txt.plan, style: theme.titleMedium))
            else ...[
              Text(
                txt.minutes(spanMinutes(j.arr - j.dep)),
                style: theme.titleMedium,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final leg in j.legs)
                        if (!leg.walking)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: RouteBadge(
                              route: catalog.routes[leg.route!],
                              fontSize: 11,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
            IconButton(
              onPressed: onOpen,
              icon: const Icon(Icons.expand_less),
              tooltip: txt.showPanel,
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.journey,
    required this.shown,
    required this.onShow,
    required this.prefer,
    required this.place,
    required this.catalog,
    required this.onStop,
    required this.onLine,
    required this.onWay,
    required this.onFollow,
  });

  final Journey journey;

  /// Whether this is the option drawn on the map; a tap toggles it. Its stops
  /// and lines take taps of their own only once it is
  final bool shown;
  final VoidCallback onShow;
  final Prefer prefer;

  /// Where an option, by its index in the plan, is in the list, from 1.
  final int Function(int option) place;
  final Catalog catalog;
  final void Function(int stop) onStop;

  final void Function(int route) onLine;
  final Future<String?> Function(WayPick? pick) onWay;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final changes = journey.rides - 1;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      shape: shown
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: material.Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      child: InkWell(
        onTap: onShow,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    txt.minutes(spanMinutes(journey.arr - journey.dep)),
                    style: material.Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Text('${clockTime(journey.dep)} - ${clockTime(journey.arr)}'),
                  const Spacer(),
                  Text(
                    journey.rides == 0
                        ? txt.wholeWalk
                        : changes <= 0
                        ? txt.noChange
                        : txt.changeCount(changes),
                    style: material.Theme.of(context).textTheme.bodySmall,
                  ),
                  if (journey.rides > 0 && journey.backup > 0)
                    InkWell(
                      onTap: () => showBackups(
                        context,
                        journey: journey,
                        prefer: prefer,
                        catalog: catalog,
                        place: place,
                        onWay: onWay,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          '· ${txt.backupCount(journey.backup)}',
                          style: material.Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.greenAccent,
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dotted,
                                decorationColor: Colors.greenAccent,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
              for (final leg in journey.legs)
                IgnorePointer(
                  ignoring: !shown,
                  child: _LegRow(
                    leg: leg,
                    catalog: catalog,
                    onStop: onStop,
                    onLine: onLine,
                  ),
                ),
              if (shown && followable(journey))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Tooltip(
                    message: txt.followHint,
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: onFollow,
                        child: Text(txt.follow),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({
    required this.leg,
    required this.catalog,
    required this.onStop,
    required this.onLine,
  });

  final Leg leg;
  final Catalog catalog;
  final void Function(int stop) onStop;

  final void Function(int route) onLine;

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final small = theme.textTheme.bodySmall;
    // A walk between two rides is a leg of its own on the wire, so it is one
    // here too: its own duration, and the stop it ends at
    final where = leg.b < 0 ? txt.toDoor : catalog.stops[leg.b].name;
    return InkWell(
      onTap: leg.b < 0 ? null : () => onStop(leg.b),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            if (leg.walking)
              SizedBox(
                width: 92,
                child: Tooltip(
                  message: txt.walkLeg(spanMinutes(leg.arr - leg.dep)),
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions_walk,
                        size: 16,
                        color: small?.color,
                      ),
                      Text(
                        txt.minutes(spanMinutes(leg.arr - leg.dep)),
                        style: small,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SizedBox(width: 44, child: Text(clockTime(leg.dep))),
              // Inside a row that opens the stop, so the badge takes its own
              // taps
              InkWell(
                onTap: () => onLine(leg.route!),
                borderRadius: BorderRadius.circular(6),
                child: RouteBadge(
                  route: catalog.routes[leg.route!],
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(where, overflow: TextOverflow.ellipsis)),
            if (legNote(leg.confidence) case (final part, final why))
              _Note(
                part: part,
                why: why,
                colour: leg.confidence == Confidence.quiet
                    ? theme.colorScheme.error
                    : small?.color,
              ),
          ],
        ),
      ),
    );
  }
}

/// A word on what a ride rests on, which explains itself when tapped.
class _Note extends StatelessWidget {
  const _Note({required this.part, required this.why, required this.colour});

  final String part;
  final String why;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final style = material.Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colour);
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(part),
          content: Text(why),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      ),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(part, style: style),
            const SizedBox(width: 2),
            Icon(Icons.info_outline, size: 14, color: colour),
          ],
        ),
      ),
    );
  }
}
