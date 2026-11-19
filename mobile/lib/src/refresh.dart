import 'dart:async';

/// How often a followed journey is searched again with "Keep the route
/// updated" on. Chosen, not derived: often enough to catch a delay, rare
/// enough to cost little.
const refreshEveryS = 30;

/// The tick that searches a followed journey again while it is on. [enabled]
/// is read at each tick, so the setting can be turned on or off under a
/// journey already followed.
class RouteRefresh {
  RouteRefresh({required this.enabled, required this.ask});

  final bool Function() enabled;
  final void Function() ask;
  Timer? _tick;

  void start() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: refreshEveryS), (_) {
      if (enabled()) ask();
    });
  }

  void stop() {
    _tick?.cancel();
    _tick = null;
  }
}
