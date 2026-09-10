/// How the phone app looks, in one place.
///
/// The five colours and two radii here are the ones `web/src/app.css` declares
/// in its `@theme` block, so the two clients are the same product seen twice.
/// `plate` and `accent` are also the two colours in `web/public/icon.svg`,
/// which is what the launcher icon is drawn from.
///
/// Depth is a hairline outline and a soft shadow rather than a raised surface:
/// Material 3's elevation tints a surface towards the seed colour, which over a
/// map reads as a second map.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

const plate = Color(0xff0b0f14);
const panel = Color(0xff121822);
const raised = Color(0xff1b2432);
const accent = Color(0xff38bdf8);
const hair = Color(0x14ffffff);

const panelRadius = 16.0;
const controlRadius = 10.0;

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: panel,
    surfaceContainerLowest: plate,
    surfaceContainerHighest: raised,
  );
  final panelShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(panelRadius),
    side: const BorderSide(color: hair),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: plate,
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      shape: panelShape,
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: plate,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: plate,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: Color(0x2638bdf8),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(panelRadius)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      shape: panelShape,
    ),
    dividerTheme: const DividerThemeData(color: hair, space: 1, thickness: 1),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(controlRadius)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: raised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: const BorderSide(color: hair),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: const BorderSide(color: hair),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
