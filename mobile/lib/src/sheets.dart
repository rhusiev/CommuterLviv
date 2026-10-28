/// The layers and account sheets, and [showFloatingSheet] that puts every
/// sheet in the app on screen.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'api.dart';
import 'map_theme.dart';
import 'strings.dart';
import 'theme.dart';

/// A sheet that floats rather than docks. `showModalBottomSheet` is docked by
/// construction, so the sheet itself is transparent and the gap is padding
/// inside it; the handle is drawn here for the same reason. The bottom inset is
/// only [floatingGap] because each sheet's own `SafeArea` clears the system bar.
Future<T?> showFloatingSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool scrollControlled = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: scrollControlled,
  // A scroll-controlled sheet may grow to the full height, under the status bar
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) => Padding(
    padding: const EdgeInsets.all(floatingGap),
    child: Material(
      color: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(panelRadius),
        side: const BorderSide(color: hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Handle(),
          Flexible(child: builder(context)),
        ],
      ),
    ),
  ),
);

/// What to call a place at a point, proposing [was]; null unless a name was given.
Future<String?> askPlaceName(BuildContext context, {String? was}) async {
  final name = await askName(
    context,
    txt.namePlace,
    was: was,
    action: txt.saveHere,
  );
  return name == null || name.isEmpty ? null : name;
}

/// The one-field dialog behind every name in the app.
Future<String?> askName(
  BuildContext context,
  String title, {
  String? was,
  String? action,
}) => showDialog<String>(
  context: context,
  builder: (context) => _NameDialog(title, was: was, action: action),
);

/// Owns its field, so the field is disposed once the dialog has closed.
class _NameDialog extends StatefulWidget {
  const _NameDialog(this.title, {this.was, this.action});

  final String title;
  final String? was;
  final String? action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _field = TextEditingController(text: widget.was);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(widget.title),
    content: TextField(controller: _field, autofocus: true),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(txt.cancel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _field.text.trim()),
        child: Text(widget.action ?? txt.save),
      ),
    ],
  );
}

/// What a long press on a saved thing offers. A thing that cannot be renamed -
/// a pinned stop wears the stop's own name - passes a null [onRename], and
/// one that is let go of rather than deleted names that in [deleteLabel].
Future<void> manage(
  BuildContext context, {
  Future<void> Function()? onRename,
  required Future<void> Function() onDelete,
  String? deleteLabel,
}) async {
  final what = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          if (onRename != null)
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(txt.rename),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(deleteLabel ?? txt.delete),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (what == 'rename') await onRename!();
  if (what == 'delete') await onDelete();
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 4,
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// Everything that changes what the map shows, in one place: the overlays as
/// switches, the basemap as a choice. Anything here is visible on the map the
/// moment it is touched, which is the rule for what belongs in this sheet
/// rather than in the Mine tab.
class LayersSheet extends StatefulWidget {
  const LayersSheet({
    super.key,
    required this.lines,
    required this.onLines,
    required this.traffic,
    required this.onTraffic,
    required this.theme,
    required this.onTheme,
    required this.blur,
    required this.onBlur,
  });

  final bool lines;
  final ValueChanged<bool> onLines;
  final bool traffic;
  final ValueChanged<bool> onTraffic;
  final MapTheme theme;
  final void Function(MapTheme theme) onTheme;
  final bool blur;
  final ValueChanged<bool> onBlur;

  @override
  State<LayersSheet> createState() => _LayersSheetState();
}

/// The sheet is its own route and the screen behind it never rebuilds it, so a
/// switch has to hold its own position while the map changes under the sheet.
class _LayersSheetState extends State<LayersSheet> {
  late bool _lines = widget.lines;
  late bool _traffic = widget.traffic;
  late MapTheme _theme = widget.theme;
  late bool _blur = widget.blur;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.polyline_outlined),
            title: Text(txt.everyRoute),
            value: _lines,
            onChanged: (on) {
              setState(() => _lines = on);
              widget.onLines(on);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.traffic_outlined),
            title: Text(txt.traffic),
            value: _traffic,
            onChanged: (on) {
              setState(() => _traffic = on);
              widget.onTraffic(on);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.blur_on),
            title: Text(txt.blur),
            value: _blur,
            onChanged: (on) {
              setState(() => _blur = on);
              widget.onBlur(on);
            },
          ),
          const Divider(height: 1),
          _Label(txt.mapStyle),
          for (final t in mapThemes)
            ListTile(
              leading: Icon(
                t.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              ),
              title: Text(txt.themeNames[t.id] ?? t.id),
              trailing: t.id == _theme.id ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _theme = t);
                widget.onTheme(t);
              },
            ),
        ],
      ),
    ),
  );
}

/// Everything that belongs to the account rather than to the map, in the order
/// it is reached for: what was kept, then how the app is set up, then the way
/// out, set apart below a rule so it is never the tap next to anything else.
class AccountSheet extends StatefulWidget {
  const AccountSheet({
    super.key,
    required this.server,
    required this.speed,
    required this.hurry,
    required this.followAway,
    required this.onFollowAway,
    required this.onLanguage,
    required this.onSpeed,
    required this.onServer,
    this.onPassword,
    required this.onOut,
  });

  final String server;

  /// The usual walking speed, km/h.
  final double speed;

  /// The hurrying speed, km/h, null when hurrying is off.
  final double? hurry;
  final bool followAway;
  final ValueChanged<bool> onFollowAway;
  final VoidCallback onLanguage;
  final VoidCallback onSpeed;
  final VoidCallback onServer;

  /// Null where the service does not let a password be changed, which hides the row.
  final VoidCallback? onPassword;
  final VoidCallback onOut;

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  late bool _followAway = widget.followAway;

  @override
  Widget build(BuildContext context) {
    final colours = material.Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(txt.language),
              trailing: Text(lang == Lang.uk ? 'Українська' : 'English'),
              onTap: widget.onLanguage,
            ),
            ListTile(
              leading: const Icon(Icons.directions_walk),
              title: Text(txt.paces),
              subtitle: Text(txt.pacesNow(widget.speed, widget.hurry)),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onSpeed,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: Text(txt.followAway),
              subtitle: Text(txt.followAwayHint),
              value: _followAway,
              onChanged: (on) {
                setState(() => _followAway = on);
                widget.onFollowAway(on);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(txt.server),
              subtitle: Text(widget.server),
              onTap: widget.onServer,
            ),
            if (widget.onPassword case final onPassword?)
              ListTile(
                leading: const Icon(Icons.password),
                title: Text(txt.changePassword),
                onTap: onPassword,
              ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: colours.error),
              title: Text(txt.signOut, style: TextStyle(color: colours.error)),
              onTap: widget.onOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(text, style: material.Theme.of(context).textTheme.labelLarge),
    ),
  );
}

class LanguageSheet extends StatelessWidget {
  const LanguageSheet({super.key, required this.api});

  final Api api;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in Lang.values)
          ListTile(
            onTap: () {
              useLang(l);
              Navigator.pop(context);
              unawaited(api.setLanguage(l.name));
            },
            title: Text(l == Lang.uk ? 'Українська' : 'English'),
            trailing: l == lang ? const Icon(Icons.check) : null,
          ),
      ],
    ),
  );
}
