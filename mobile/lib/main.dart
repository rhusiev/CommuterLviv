/// Lviv's buses, on a phone.
///
/// The app is a second client for the same service the web UI talks to; it adds
/// no endpoint and no model. What it does not share is the browser, so
/// `src/api.dart` is the small amount of browser it has to be, and everything
/// drawn on the map is drawn by `src/vehicle_layer.dart` rather than by a
/// canvas over MapLibre.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/api.dart';
import 'src/home.dart';
import 'src/sign_in.dart';
import 'src/strings.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await Api.open();
  // Also settles where the basemap comes from, which the map reads before the
  // sign-in screen would have asked - a resumed session never sees that screen.
  // A server that cannot be reached leaves the public tile server standing
  await api.health().catchError((_) => 'code');
  useLang(
    Lang.values.firstWhere((l) => l.name == api.language, orElse: phoneLang),
  );
  runApp(CommuterLvivApp(api: api));
}

/// iOS users expect a back swipe and a sliding page; Android users expect
/// neither. One widget tree, two sets of manners.
bool get _cupertino => !kIsWeb && Platform.isIOS;

class CommuterLvivApp extends StatefulWidget {
  const CommuterLvivApp({super.key, required this.api});

  final Api api;

  @override
  State<CommuterLvivApp> createState() => _CommuterLvivAppState();
}

class _CommuterLvivAppState extends State<CommuterLvivApp> {
  String? _user;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _resume();
  }

  /// A session that survived the last run, or a remember-me cookie the service
  /// will trade for one. Either way the sign-in screen is never shown to
  /// someone already signed in.
  Future<void> _resume() async {
    String? who;
    try {
      who = (await widget.api.me()).username;
    } on Exception {
      who = null;
    }
    if (mounted) {
      setState(() {
        _user = who;
        _checked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Everything says what `txt` said when it was last built, so switching
    // language is one rebuild of the whole tree and nothing below has to know
    return ListenableBuilder(
      listenable: langChanged,
      builder: (context, _) => MaterialApp(
        title: 'CommuterLviv',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        home: !_checked
            ? const _Splash()
            : _user == null
            ? SignInScreen(
                api: widget.api,
                onIn: (name) => setState(() => _user = name),
              )
            : HomeScreen(
                api: widget.api,
                username: _user!,
                onOut: () => setState(() => _user = null),
                key: ValueKey(_user),
              ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
}

/// Haptics on the actions that move the map under the user, so a tap that flies
/// the camera feels like it did something even before the animation starts
void tick() {
  if (_cupertino) {
    HapticFeedback.selectionClick();
  } else {
    HapticFeedback.lightImpact();
  }
}

bool get isCupertino => _cupertino;
