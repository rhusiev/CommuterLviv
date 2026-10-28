/// One way the planner found, as a card. Unpicked, the whole card is one tap
/// target that picks it, and says in words what is worth knowing. Picked, its
/// summary folds it again, and below it the legs open: a stop is a row with a
/// chevron, a line a ringed badge with a map, and every note is said in full.
library;

import 'package:flutter/material.dart';

import 'backups_dialog.dart';
import 'eta.dart';
import 'follow.dart' show followable, plannedKmh;
import 'hurry_pill.dart';
import 'models.dart';
import 'route_badge.dart';
import 'strings.dart';

/// A word on a ride not resting on a tracked vehicle, and what it means; null
/// on one that is.
(String, String)? legNote(Confidence confidence) => switch (confidence) {
  Confidence.live => null,
  Confidence.terminus => (txt.terminusPart, txt.terminusWhy),
  Confidence.schedule => (txt.schedulePart, txt.scheduleWhy),
  Confidence.quiet => (txt.quietPart, txt.quietWhy),
};

/// A ride's note, and none on a walk
(String, String)? _noteOn(Leg leg) =>
    leg.walking ? null : legNote(leg.confidence);

/// What leads a row, before what it names: a walk's minutes, a ride's clock
const _leadWidth = 64.0;
const _gap = 8.0;
const _smallIconSize = 16.0;
const _cornerRadius = 12.0;
const _shownBorderWidth = 2.0;

/// The backups count, the same open or closed, so it is seen before opening
const _backupColour = Colors.greenAccent;

/// Under half a minute at the stop is boarding, not waiting
const _waitSaidS = 30;

/// The seconds stood at the stop before leg [i], a ride, leaves
int _waitBefore(Journey journey, int i) =>
    journey.legs[i].dep - (i > 0 ? journey.legs[i - 1].arr : journey.dep);

/// An option caught only by hurrying: what its pill says, with the pace that
/// catches it, and why
(String, String) _hurried(Journey journey) {
  final kmh = plannedKmh(journey);
  return kmh == null
      ? (txt.hurry, txt.hurryHint)
      : (txt.hurryAt(txt.kmh(kmh)), '${txt.hurryHint}. ${txt.paceHint}');
}

/// How loudly a note is said: a line unseen in the error colour, the rest quiet
Color? _noteColour(ThemeData theme, Confidence confidence) =>
    confidence == Confidence.quiet
    ? theme.colorScheme.error
    : theme.textTheme.bodySmall?.color;

class JourneyOption extends StatelessWidget {
  const JourneyOption({
    super.key,
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

  /// Whether this is the option drawn on the map, and opened
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
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: _gap),
    clipBehavior: Clip.antiAlias,
    shape: shown
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cornerRadius),
            side: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: _shownBorderWidth,
            ),
          )
        : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: shown,
          child: InkWell(
            onTap: onShow,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: _Summary(journey: journey, catalog: catalog, shown: shown),
            ),
          ),
        ),
        if (shown)
          _Opened(
            journey: journey,
            catalog: catalog,
            onStop: onStop,
            onLine: onLine,
            onBackups: () => showBackups(
              context,
              journey: journey,
              prefer: prefer,
              catalog: catalog,
              place: place,
              onWay: onWay,
            ),
            onFollow: onFollow,
          ),
      ],
    ),
  );
}

/// What a tap on folds or opens: the length, the legs in a line, and while
/// folded what is worth knowing, said in words
class _Summary extends StatelessWidget {
  const _Summary({
    required this.journey,
    required this.catalog,
    required this.shown,
  });

  final Journey journey;
  final Catalog catalog;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final changes = journey.rides - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              txt.minutes(spanMinutes(journey.arr - journey.dep)),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(width: _gap),
            Text('${clockTime(journey.dep)} - ${clockTime(journey.arr)}'),
            const SizedBox(width: _gap),
            Expanded(
              child: Text(
                journey.rides == 0
                    ? txt.wholeWalk
                    : changes <= 0
                    ? txt.noChange
                    : txt.changeCount(changes),
                style: small,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              shown ? Icons.expand_less : Icons.expand_more,
              color: small?.color,
            ),
          ],
        ),
        const SizedBox(height: 6),
        _Strip(journey: journey, catalog: catalog),
        if (!shown) _Flags(journey: journey),
      ],
    );
  }
}

/// The legs in a line: a walk by its minutes, a ride by the minutes waited for
/// it, its line's badge and the minutes ridden, with a dot where a ride rests
/// on more than a tracked vehicle
class _Strip extends StatelessWidget {
  const _Strip({required this.journey, required this.catalog});

  final Journey journey;
  final Catalog catalog;

  static const _dotSize = 6.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final legs = journey.legs;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, leg) in legs.indexed) ...[
          if (i > 0)
            Icon(
              Icons.chevron_right,
              size: _smallIconSize,
              color: _dimmed(small),
            ),
          if (leg.walking)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_walk,
                  size: _smallIconSize,
                  color: small?.color,
                ),
                Text('${spanMinutes(leg.arr - leg.dep)}', style: small),
              ],
            )
          else
            _StripRide(
              leg: leg,
              wait: _waitBefore(journey, i),
              catalog: catalog,
            ),
          if (_noteOn(leg) != null)
            Container(
              width: _dotSize,
              height: _dotSize,
              decoration: BoxDecoration(
                color: _noteColour(theme, leg.confidence),
                shape: BoxShape.circle,
              ),
            ),
        ],
      ],
    );
  }
}

/// A ride in the strip: the minutes waited for it, by a clock, then its line's
/// badge and the minutes ridden
class _StripRide extends StatelessWidget {
  const _StripRide({
    required this.leg,
    required this.wait,
    required this.catalog,
  });

  final Leg leg;
  final int wait;
  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final ride = spanMinutes(leg.arr - leg.dep);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (wait >= _waitSaidS)
          Tooltip(
            message: txt.waitLeg(spanMinutes(wait)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: _smallIconSize, color: small?.color),
                Text('${spanMinutes(wait)}', style: small),
              ],
            ),
          ),
        if (catalog.routeAt(leg.route) case final route?)
          RouteBadge(route: route, fontSize: 11),
        Tooltip(
          message: txt.rideLeg(ride),
          child: Text('$ride', style: small),
        ),
      ],
    );
  }
}

/// A dimmer shade of a text style's colour, for what only separates
Color? _dimmed(TextStyle? style) => style?.color?.withValues(alpha: 0.5);

/// What a folded card says beyond its legs, only as words: the hurry, the
/// loudest note, and the backups
class _Flags extends StatelessWidget {
  const _Flags({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final noted = journey.legs.where((l) => _noteOn(l) != null);
    final loudest =
        noted.where((l) => l.confidence == Confidence.quiet).firstOrNull ??
        noted.firstOrNull;
    final backups = journey.rides > 0 && journey.backup > 0;
    if (!journey.hurry && loudest == null && !backups) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: _gap,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (journey.hurry)
            switch (_hurried(journey)) {
              (final text, final hint) => HurryPill(
                text: text,
                hint: hint,
                explains: false,
              ),
            },
          if (loudest != null)
            Text(
              legNote(loudest.confidence)!.$1,
              style: small?.copyWith(
                color: _noteColour(theme, loudest.confidence),
              ),
            ),
          if (backups)
            Text(
              txt.backupCount(journey.backup),
              style: small?.copyWith(color: _backupColour),
            ),
        ],
      ),
    );
  }
}

/// The picked card's legs, each control drawn as one, and what it leads to
class _Opened extends StatelessWidget {
  const _Opened({
    required this.journey,
    required this.catalog,
    required this.onStop,
    required this.onLine,
    required this.onBackups,
    required this.onFollow,
  });

  final Journey journey;
  final Catalog catalog;
  final void Function(int stop) onStop;
  final void Function(int route) onLine;
  final VoidCallback onBackups;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final legs = journey.legs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, _gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          if (journey.hurry)
            switch (_hurried(journey)) {
              (final text, final hint) => Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HurryPill(text: text, hint: hint, explains: false),
                    const SizedBox(height: 4),
                    Text(hint, style: small),
                  ],
                ),
              ),
            },
          for (final (i, leg) in legs.indexed) ...[
            if (!leg.walking) _Wait(seconds: _waitBefore(journey, i)),
            leg.walking
                ? _Walk(
                    leg: leg,
                    // Consecutive walks are folded before they are sent, so a
                    // walk with a ride either side is the change itself
                    change: i > 0 && i < legs.length - 1,
                    catalog: catalog,
                    onStop: onStop,
                  )
                : _Ride(
                    leg: leg,
                    catalog: catalog,
                    onStop: onStop,
                    onLine: onLine,
                  ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                if (journey.rides > 0 && journey.backup > 0)
                  TextButton(
                    onPressed: onBackups,
                    style: TextButton.styleFrom(
                      foregroundColor: _backupColour,
                      minimumSize: const Size.square(kMinInteractiveDimension),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(txt.backupCount(journey.backup)),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                if (followable(journey))
                  Expanded(
                    child: Tooltip(
                      message: txt.followHint,
                      child: FilledButton.tonal(
                        onPressed: onFollow,
                        child: Text(txt.follow),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Walk extends StatelessWidget {
  const _Walk({
    required this.leg,
    required this.change,
    required this.catalog,
    required this.onStop,
  });

  final Leg leg;

  /// Whether it is the walk between two rides
  final bool change;
  final Catalog catalog;
  final void Function(int stop) onStop;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final minutes = spanMinutes(leg.arr - leg.dep);
    final lead = _MinutesLead(
      icon: Icons.directions_walk,
      minutes: minutes,
      said: txt.walkLeg(minutes),
    );
    if (leg.b < 0) {
      return _Row(
        lead: lead,
        child: Text(txt.toDoor, style: small),
      );
    }
    final name = catalog.stopName(leg.b);
    return _StopRow(
      lead: lead,
      name: change ? txt.changeAt(name) : name,
      onTap: () => onStop(leg.b),
    );
  }
}

/// The minutes stood at the stop before a ride, once there are any
class _Wait extends StatelessWidget {
  const _Wait({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    if (seconds < _waitSaidS) return const SizedBox.shrink();
    final minutes = spanMinutes(seconds);
    return _Row(
      lead: _MinutesLead(
        icon: Icons.schedule,
        minutes: minutes,
        said: txt.waitLeg(minutes),
      ),
      child: Text(txt.wait, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// A row's lead: minutes after an icon, said in full by its tooltip
class _MinutesLead extends StatelessWidget {
  const _MinutesLead({
    required this.icon,
    required this.minutes,
    required this.said,
  });

  final IconData icon;
  final int minutes;
  final String said;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Tooltip(
      message: said,
      child: Row(
        children: [
          Icon(icon, size: _smallIconSize, color: small?.color),
          Flexible(
            child: Text(
              txt.minutes(minutes),
              style: small,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ride extends StatelessWidget {
  const _Ride({
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
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final note = _noteOn(leg);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(_gap),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            lead: Text(clockTime(leg.dep)),
            child: Row(
              children: [
                if (catalog.routeAt(leg.route) case final route?)
                  _LineButton(route: route, onTap: () => onLine(leg.route!)),
                Text(txt.rideLeg(spanMinutes(leg.arr - leg.dep)), style: small),
                const Spacer(),
                if (note case (final part, _))
                  Text(
                    part,
                    style: small?.copyWith(
                      color: _noteColour(theme, leg.confidence),
                    ),
                  ),
              ],
            ),
          ),
          if (note case (_, final why))
            Padding(
              padding: const EdgeInsets.fromLTRB(_gap + _leadWidth, 0, _gap, 4),
              child: Text(why, style: small),
            ),
          _StopRow(
            lead: Icon(
              Icons.place_outlined,
              size: _smallIconSize,
              color: small?.color,
            ),
            name: catalog.stopName(leg.b),
            onTap: () => onStop(leg.b),
          ),
        ],
      ),
    );
  }
}

/// A ride's line, in a ring with a map, which shows the line
class _LineButton extends StatelessWidget {
  const _LineButton({required this.route, required this.onTap});

  final TransitRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: txt.showLine,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinInteractiveDimension,
            minHeight: kMinInteractiveDimension,
          ),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.fromLTRB(3, 3, _gap, 3),
              decoration: ShapeDecoration(
                shape: StadiumBorder(
                  side: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RouteBadge(route: route, fontSize: 11),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.map_outlined,
                    size: _smallIconSize,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that opens a stop's card, by its chevron
class _StopRow extends StatelessWidget {
  const _StopRow({required this.lead, required this.name, required this.onTap});

  final Widget lead;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(_gap),
    child: _Row(
      lead: lead,
      child: Row(
        children: [
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ],
      ),
    ),
  );
}

/// A leg's row, as tall as a finger needs: what leads it, then what it names
class _Row extends StatelessWidget {
  const _Row({required this.lead, required this.child});

  final Widget lead;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gap),
      child: Row(
        children: [
          SizedBox(width: _leadWidth, child: lead),
          Expanded(child: child),
        ],
      ),
    ),
  );
}
