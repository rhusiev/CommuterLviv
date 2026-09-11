/// How the app looks, in one place. Depth is a hairline outline and a shadow
/// rather than elevation, which tints a surface towards the seed colour and
/// over a map reads as a second map. Nothing docks to an edge: [floatingTop]
/// and [floatingBottom] are how anything works out what it has to clear.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

const plate = Color(0xff0b0f14);
const panel = Color(0xff121822);
const raised = Color(0xff1b2432);
const accent = Color(0xff38bdf8);
const hair = Color(0x14ffffff);

const panelRadius = 20.0;
const controlRadius = 12.0;

/// The gap every floating thing leaves, and the heights of the two bars.
const floatingGap = 12.0;
const topBarHeight = 48.0;
const tabBarHeight = 52.0;

double floatingTop(BuildContext context) =>
    MediaQuery.paddingOf(context).top + topBarHeight + floatingGap * 2;

double floatingBottom(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + tabBarHeight + floatingGap * 2;

const stadium = StadiumBorder(side: BorderSide(color: hair));
const circle = CircleBorder(side: BorderSide(color: hair));

/// The look every control floating over the map shares. The surface tint is
/// off because it pulls a surface towards the seed colour, which over a map
/// reads as a second map.
class Floating extends StatelessWidget {
  const Floating({
    super.key,
    required this.child,
    this.shape = stadium,
    this.elevation = 2,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final ShapeBorder shape;
  final double elevation;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) => Material(
    color: panel.withValues(alpha: 0.9),
    surfaceTintColor: Colors.transparent,
    shape: shape,
    elevation: elevation,
    clipBehavior: clipBehavior,
    child: child,
  );
}

/// One round button floating over the map.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Floating(
    shape: circle,
    child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: child),
  );
}

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
    // `showFloatingSheet` stands every sheet off the bottom edge, so square
    // corners there would read as cropped
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(panelRadius),
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
