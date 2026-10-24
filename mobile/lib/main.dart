/// Lviv's buses, on a phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/api.dart';
import 'src/home.dart';
import 'src/sign_in.dart';
import 'src/strings.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await Api.open();
  // Must run before the map builds: it settles where the basemap comes from,
  // and a resumed session never passes through the sign-in screen
  await api.health().catchError((_) => 'code');
  useLang(
    Lang.values.firstWhere((l) => l.name == api.language, orElse: phoneLang),
  );
  runApp(CommuterLvivApp(api: api));
}

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

  /// A session that survived the last run, or a remember-me cookie traded for one.
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
    return ListenableBuilder(
      listenable: langChanged,
      builder: (context, _) => MaterialApp(
        title: 'CommuterLviv',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        // Flutter's own words - the date and time pickers, Back, the screen
        // reader's labels - and the pickers' first weekday follow the app's
        // language, not the phone's
        locale: Locale(lang.name),
        supportedLocales: [for (final l in Lang.values) Locale(l.name)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
