/// Door to door: two points, and the ways between them. A ride not resting on a
/// tracked vehicle says so, and why that matters.
library;

export 'end_field.dart' show End;
export 'journey_option.dart' show legNote;

import 'dart:async';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'backups_dialog.dart';
import 'end_field.dart';
import 'eta.dart';
import 'journey_option.dart';
import 'models.dart';
import 'route_badge.dart';
import 'sheets.dart';
import 'strings.dart';
import 'theme.dart';
import 'walk_speed.dart';

class JourneyPanel extends StatefulWidget {
  const JourneyPanel({
    super.key,
    required this.api,
    required this.catalog,
    required this.from,
    this.aboard,
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
    this.named = const {},
    required this.onSave,
    required this.onPlace,
    required this.onShow,
    required this.onFollow,
    required this.ask,
    required this.onAsked,
  });

  final Api api;
  final Catalog catalog;
  final LatLng? from;

  /// The journey starts on board this vehicle, in place of [from]; it leaves
  /// now, so there is no time to leave at
  final Aboard? aboard;
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

  /// What ends were called where they were chosen, outside the panel
  final Map<LatLng, String> named;
  final void Function(String name, LatLng at) onSave;
  final void Function(End end, LatLng at) onPlace;

  /// The option picked to be drawn on the map, or null once none is
  final void Function(Journey? journey) onShow;
  final void Function(Journey journey) onFollow;

  /// Search as soon as both ends are set, once, then say so through [onAsked]
  final bool ask;
  final VoidCallback onAsked;

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

  String? _nameOf(LatLng? at) => _names[at] ?? widget.named[at];

  /// Unix seconds to leave at; null is now, which is what the server assumes.
  int? _at;

  late Prefer _prefer = widget.api.prefer;
  late Set<String> _avoid = widget.api.avoid;

  /// km/h on the level, starting from the one kept as the usual.
  late double _speed = widget.api.walkSpeed;

  /// A search asked for is waiting for the frame to end
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _askIfReady();
  }

  @override
  void didUpdateWidget(JourneyPanel old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from ||
        old.aboard != widget.aboard ||
        old.to != widget.to ||
        old.catalog != widget.catalog) {
      _forget();
    }
    _askIfReady();
  }

  bool get _ready =>
      (widget.from != null || widget.aboard != null) && widget.to != null;

  /// Searching changes the parent's state, which a build may not do
  void _askIfReady() {
    if (!widget.ask || _asking) return;
    _asking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _asking = false;
      if (!mounted || !widget.ask || !_ready) return;
      widget.onAsked();
      unawaited(_search());
    });
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

  void _orderBy(Prefer p) {
    setState(() => _prefer = p);
    widget.api.setPrefer(p);
  }

  void _toggleMode(String mode) {
    final next = {..._avoid};
    if (!next.remove(mode)) next.add(mode);
    setState(() => _avoid = next);
    unawaited(widget.api.setAvoid(next));
    // Shown options rode what is now left out: ask again
    if (_options != null) unawaited(_search());
  }

  Future<void> _search() async {
    final from = widget.from;
    final aboard = widget.aboard;
    final to = widget.to;
    if ((from == null && aboard == null) || to == null) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final got = await widget.api.plan(
        from,
        to,
        aboard: aboard,
        at: aboard == null ? _at : null,
        speed: _speed,
        hurry: widget.api.hurrySpeed,
        avoid: _avoid,
      );
      if (!mounted) return;
      setState(() {
        _options = got.options;
        _report = got.report;
        _reportSaid = null;
        _held = (id: got.report, built: {}, from: {});
      });
      _show(null);
    } on Exception catch (e) {
      final preparing = e is ApiError && e.preparing;
      if (mounted) {
        setState(
          () => _failed = preparing
              ? txt.plannerPreparing
              : widget.api.failure(e),
        );
      }
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
    final riding = j.legs[pick.leg].backups[pick.n].option;
    if (riding >= 0) return _showNow(options[riding]);
    final kept = _held;
    final option = kept.from[j] ?? options.indexOf(j);
    final way = '$option ${pick.leg} ${pick.n}';
    var got = kept.built[way];
    if (got == null) {
      final id = kept.id;
      if (id == null) return txt.searchAgain;
      try {
        got = await widget.api.backup(id, option, pick.leg, pick.n);
      } on Exception catch (e) {
        return widget.api.failure(e);
      }
      // a search made meanwhile has options of its own
      if (!mounted || !identical(_held.built, kept.built)) return null;
      kept.built[way] = got;
      kept.from[got] = option;
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
    } on Exception catch (e) {
      failed = widget.api.failure(e);
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
    final aboard = widget.aboard;
    final ready = _ready;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          for (final end in End.values)
            EndField(
              end: end,
              at: end == End.from ? widget.from : widget.to,
              aboard: end == End.from ? aboard : null,
              api: widget.api,
              catalog: widget.catalog,
              onPick: () => widget.onPick(end),
              onHere: () => widget.onHere(end),
              name: _nameOf(end == End.from ? widget.from : widget.to),
              places: widget.places,
              onPlace: (at, name) {
                if (name != null) _names[at] = name;
                widget.onPlace(end, at);
              },
              onSave: widget.onSave,
            ),
          _when(),
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
          if (_options != null) Flexible(child: _results()),
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

  Widget _header(BuildContext context) => Row(
    children: [
      Text(txt.plan, style: material.Theme.of(context).textTheme.titleMedium),
      const Spacer(),
      IconButton(
        onPressed: widget.aboard == null ? widget.onSwap : null,
        icon: const Icon(Icons.swap_vert),
        tooltip: txt.swap,
      ),
      IconButton(
        onPressed: () => widget.onFold(true),
        icon: const Icon(Icons.expand_more),
        tooltip: txt.hidePanel,
      ),
    ],
  );

  /// The chips' shape, the same as the fields' above them
  static const _pill = StadiumBorder();

  /// When to set off - unless already on board - and how to rank the options.
  Widget _when() => Row(
    children: [
      if (widget.aboard == null) ...[
        RowLabel(text: txt.departAt, icon: Icons.schedule),
        Tooltip(
          message: txt.leaveOn,
          child: ActionChip(
            label: Text(_dayName(_leaving)),
            onPressed: _pickDay,
            shape: _pill,
          ),
        ),
        const SizedBox(width: 8),
        InputChip(
          label: Text(_at == null ? txt.now : clockTime(_at!)),
          shape: _pill,
          onPressed: _pickTime,
          onDeleted: _at == null ? null : () => _leave(null),
        ),
      ],
      const Spacer(),
      // How the options are ordered, and below a rule the vehicle types they
      // may ride: rarely left out, so here rather than in a row of its own,
      // with a dot on the button while one is
      PopupMenuButton<Object>(
        icon: Badge(
          isLabelVisible: _avoid.isNotEmpty,
          smallSize: 6,
          backgroundColor: Colors.amber,
          child: const Icon(Icons.sort),
        ),
        tooltip: [
          '${txt.preferBy}: ${txt.prefer(_prefer)}',
          if (_avoid.isNotEmpty)
            txt.leftOut([for (final m in _avoid) txt.kinds[m] ?? m].join(', ')),
        ].join('. '),
        initialValue: _prefer,
        onSelected: (picked) => switch (picked) {
          final Prefer p => _orderBy(p),
          final String mode => _toggleMode(mode),
          _ => null,
        },
        itemBuilder: (_) => [
          for (final p in Prefer.values)
            PopupMenuItem(value: p, child: Text(txt.prefer(p))),
          const PopupMenuDivider(),
          for (final m in modes)
            CheckedPopupMenuItem(
              value: m,
              checked: !_avoid.contains(m),
              // The last type left cannot go: there would be nothing to ride
              enabled: _avoid.contains(m) || _avoid.length < modes.length - 1,
              child: Text(txt.kinds[m] ?? m),
            ),
        ],
      ),
    ],
  );

  Widget _results() {
    final options = _options!;
    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(txt.noJourney),
      );
    }
    final ranked = _prefer.ranked(options);
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: ranked.length,
      itemBuilder: (_, i) => JourneyOption(
        journey: ranked[i],
        shown: ranked[i] == _shown,
        onShow: () =>
            setState(() => _show(ranked[i] == _shown ? null : ranked[i])),
        prefer: _prefer,
        place: (i) => ranked.indexOf(options[i]) + 1,
        catalog: widget.catalog,
        onStop: widget.onStop,
        onLine: widget.onLine,
        onWay: (pick) => _takeWay(ranked[i], pick),
        onFollow: () => widget.onFollow(ranked[i]),
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
                        if (catalog.routeAt(leg.route) case final route?)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: RouteBadge(route: route, fontSize: 11),
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
