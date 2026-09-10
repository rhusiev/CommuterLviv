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
///
/// Nothing is docked to an edge. The map is the whole window and the bar, the
/// tab pill, the cards and the planner all float over it, so each stands off
/// the safe area rather than eating it - [floatingTop] and [floatingBottom] are
/// how anything else works out what it has to clear.
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

/// The gap every floating thing leaves against the screen and against its
/// neighbours, and how tall the two pieces of chrome are
const floatingGap = 12.0;
const topBarHeight = 48.0;
const tabBarHeight = 52.0;

double floatingTop(BuildContext context) =>
    MediaQuery.paddingOf(context).top + topBarHeight + floatingGap * 2;

double floatingBottom(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + tabBarHeight + floatingGap * 2;

/// One round button floating over the map: the drawer, locate, zoom. The same
/// surface in every corner, so nothing has to restate what floating looks like.
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
  Widget build(BuildContext context) => Material(
    color: panel.withValues(alpha: 0.9),
    surfaceTintColor: Colors.transparent,
    shape: const CircleBorder(side: BorderSide(color: hair)),
    elevation: 2,
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
    // Rounded all the way round: `showFloatingSheet` stands every sheet off the
    // bottom edge, so a sheet with two square corners would read as cropped
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
