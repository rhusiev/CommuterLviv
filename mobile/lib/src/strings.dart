/// Ukrainian and English, switchable while the app is running. `txt` is a
/// top-level value read in `build`, and `langChanged` rebuilds from the root
/// once it has moved.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'models.dart' show Prefer;

enum Lang { uk, en }

class Strings {
  const Strings({
    required this.signIn,
    required this.tagline,
    required this.inviteCode,
    required this.inviteHint,
    required this.username,
    required this.password,
    required this.passwordHint,
    required this.changePassword,
    required this.currentPassword,
    required this.newPassword,
    required this.passwordChanged,
    required this.stayIn,
    required this.createAccount,
    required this.join,
    required this.haveAccount,
    required this.wantAccount,
    required this.haveInvite,
    required this.map,
    required this.mine,
    required this.lines,
    required this.allLines,
    required this.watchingLines,
    required this.nearLines,
    required this.nothingNearLines,
    required this.noneWatched,
    required this.recentLines,
    required this.otherWay,
    required this.watchLine,
    required this.noLineStops,
    required this.vehicleHere,
    required this.mapStyle,
    required this.themeNames,
    required this.server,
    required this.signOut,
    required this.routes,
    required this.kinds,
    required this.everyRoute,
    required this.layers,
    required this.attributions,
    required this.account,
    required this.findStop,
    required this.tryAgain,
    required this.filterRoutes,
    required this.clear,
    required this.saveAsSet,
    required this.updateSet,
    required this.nameSet,
    required this.rename,
    required this.delete,
    required this.places,
    required this.savePlace,
    required this.getHere,
    required this.namePlace,
    required this.thisPlace,
    required this.savePlaceAs,
    required this.placeNameTaken,
    required this.placeMoved,
    required this.toHere,
    required this.fromHere,
    required this.nearHere,
    required this.nothingNearHere,
    required this.noPlaces,
    required this.saved,
    required this.pinnedStops,
    required this.saveHow,
    required this.holdToManage,
    required this.foundStops,
    required this.foundPlaces,
    required this.noSearch,
    required this.nearMe,
    required this.nothingNear,
    required this.nothingFound,
    required this.traffic,
    required this.departAt,
    required this.preferBy,
    required this.quietPart,
    required this.saveHere,
    required this.cancel,
    required this.save,
    required this.use,
    required this.sets,
    required this.noSets,
    required this.pin,
    required this.unpin,
    required this.callsHere,
    required this.nothingDue,
    required this.pickARoute,
    required this.pinAStop,
    required this.language,
    required this.noBasemap,
    required this.faceNorth,
    required this.zoomIn,
    required this.zoomOut,
    required this.whereAmI,
    required this.noLocation,
    required this.renewed,
    required this.quietTitle,
    required this.quietDetail,
    required this.plannerPreparing,
    required this.stopsAhead,
    required this.vehicleGone,
    required this.onIt,
    required this.onItHint,
    required this.aboard,
    required this.now,
    required this.oneMinute,
    required this.plan,
    required this.from,
    required this.to,
    required this.tapMap,
    required this.useHere,
    required this.swap,
    required this.findRoute,
    required this.searching,
    required this.noJourney,
    required this.report,
    required this.reportNote,
    required this.reported,
    required this.send,
    required this.toDoor,
    required this.noChange,
    required this.prefer,
    required this.schedulePart,
    required this.chooseOnMap,
    required this.hidePanel,
    required this.showPanel,
    required this.leaveOn,
    required this.paces,
    required this.pacesNow,
    required this.walkSpeed,
    required this.walkSpeedHint,
    required this.hurrySpeed,
    required this.hurrySpeedHint,
    required this.hurry,
    required this.hurryHint,
    required this.hurryAt,
    required this.paceHint,
    required this.slower,
    required this.faster,
    required this.alsoOptionHint,
    required this.showWay,
    required this.showLine,
    required this.lineOf,
    required this.watchRoute,
    required this.unwatchRoute,
    required this.searchAgain,
    required this.today,
    required this.tomorrow,
    required this.backups,
    required this.backupsWhy,
    required this.noBackup,
    required this.moreBackups,
    required this.scheduleWhy,
    required this.terminusPart,
    required this.terminusWhy,
    required this.quietWhy,
    required this.wholeWalk,
    required this.planHint,
    required this.follow,
    required this.followHint,
    required this.endFollow,
    required this.locating,
    required this.walkTo,
    required this.walkHome,
    required this.waitAt,
    required this.showSteps,
    required this.hideSteps,
    required this.dueIn,
    required this.offAt,
    required this.offSoon,
    required this.toGo,
    required this.passedStop,
    required this.offTheWay,
    required this.hurryNow,
    required this.hurryAhead,
    required this.noLonger,
    required this.missedRide,
    required this.findAnother,
    required this.planAgain,
    required this.followAway,
    required this.followAwayHint,
    required this.followChannel,
    required this.alertChannel,
    required this.arrived,
    required this.metres,
    required this.km,
    required this.walkLeg,
    required this.changeCount,
    required this.changeAt,
    required this.backupCount,
    required this.shortDay,
    required this.minutes,
    required this.kmh,
    required this.alsoOption,
    required this.unreachable,
  });

  final String signIn;
  final String tagline;
  final String inviteCode;
  final String inviteHint;
  final String username;
  final String password;
  final String passwordHint;
  final String changePassword;
  final String currentPassword;
  final String newPassword;

  /// Said once the service has taken it, and signed every other device out.
  final String passwordChanged;
  final String stayIn;
  final String createAccount;
  final String join;
  final String haveAccount;
  final String wantAccount;
  final String haveInvite;
  final String map;
  final String mine;

  /// The routes, and one line of them open; "Lines" so it does not read as the
  /// journey tab in Ukrainian, which spends "Маршрут" on a route
  final String lines;
  final String allLines;
  final String Function(int n) watchingLines;
  final String nearLines;
  final String Function(int metres) nothingNearLines;
  final String noneWatched;
  final String recentLines;
  final String otherWay;
  final String watchLine;
  final String noLineStops;
  final String vehicleHere;
  final String mapStyle;

  /// Each basemap's name, by its [MapTheme.id].
  final Map<String, String> themeNames;
  final String server;
  final String signOut;
  final String routes;

  /// Headings over the route chips, by `TransitRoute.type`
  final Map<String, String> kinds;

  final String everyRoute;
  final String layers;

  /// The map's ⓘ, which opens the credits for its data and tiles
  final String attributions;
  final String account;
  final String findStop;
  final String tryAgain;
  final String filterRoutes;
  final String clear;
  final String saveAsSet;
  final String Function(String name) updateSet;
  final String nameSet;
  final String rename;
  final String delete;
  final String places;
  final String savePlace;

  /// Plans the way to a place shown on the map
  final String getHere;
  final String namePlace;

  /// A point held on the map, and what its sheet offers for it
  final String thisPlace;
  final String savePlaceAs;

  /// A rename refused: the name is a place's identity on the server, so a
  /// second place of that name would replace the first
  final String placeNameTaken;

  /// Saving under a saved place's name moves that place
  final String Function(String name) placeMoved;
  final String toHere;
  final String fromHere;
  final String nearHere;
  final String nothingNearHere;
  final String noPlaces;
  final String saved;
  final String pinnedStops;

  /// Where places get saved from, for an empty list of them
  final String saveHow;

  final String holdToManage;
  final String foundStops;
  final String foundPlaces;
  final String noSearch;
  final String nearMe;
  final String nothingNear;
  final String nothingFound;
  final String traffic;
  final String departAt;
  final String preferBy;

  /// The timetable on a line nothing has been seen running on.
  final String quietPart;
  final String saveHere;
  final String cancel;
  final String save;
  final String use;
  final String sets;

  /// Where sets are made, for an empty list of them
  final String noSets;
  final String pin;
  final String unpin;
  final String callsHere;
  final String nothingDue;
  final String pickARoute;
  final String pinAStop;
  final String language;
  final String noBasemap;
  final String faceNorth;
  final String zoomIn;
  final String zoomOut;
  final String whereAmI;

  /// Location refused or switched off: the phone does not say which to the app.
  final String noLocation;

  /// The service moved to new routes and timetables while the app was open.
  final String renewed;

  /// Too few vehicles report for what the timetable has running.
  final String quietTitle;
  final String quietDetail;

  final String plannerPreparing;
  final String stopsAhead;
  final String vehicleGone;
  final String onIt;
  final String onItHint;
  final String aboard;
  final String now;
  final String oneMinute;
  final String plan;
  final String from;
  final String to;
  final String tapMap;
  final String useHere;
  final String swap;
  final String findRoute;
  final String searching;
  final String noJourney;
  final String report;
  final String reportNote;
  final String reported;
  final String send;
  final String toDoor;
  final String noChange;
  final String Function(Prefer p) prefer;
  final String schedulePart;
  final String chooseOnMap;
  final String hidePanel;
  final String showPanel;
  final String leaveOn;
  final String paces;

  /// The usual walking speed and the hurrying one, null when hurrying is off.
  final String Function(double walk, double? hurry) pacesNow;
  final String walkSpeed;
  final String walkSpeedHint;
  final String hurrySpeed;
  final String hurrySpeedHint;
  final String hurry;
  final String hurryHint;

  /// Hurrying, and the [pace] that catches the bus with time to spare
  final String Function(String pace) hurryAt;
  final String paceHint;
  final String slower;
  final String faster;
  final String alsoOptionHint;
  final String showWay;
  final String showLine;

  /// What the `›` of a route chip is called for [route], read out by a screen reader.
  final String Function(String route) lineOf;
  final String watchRoute;
  final String unwatchRoute;
  final String searchAgain;
  final String today;
  final String tomorrow;
  final String backups;
  final String backupsWhy;
  final String noBackup;
  final String Function(int more) moreBackups;
  final String scheduleWhy;
  final String terminusPart;
  final String terminusWhy;
  final String quietWhy;
  final String wholeWalk;
  final String planHint;
  final String follow;
  final String followHint;
  final String endFollow;
  final String locating;
  final String Function(String stop) walkTo;
  final String walkHome;
  final String Function(String stop) waitAt;
  final String showSteps;
  final String hideSteps;
  final String Function(String when) dueIn;
  final String Function(String stop) offAt;
  final String Function(String stop) offSoon;
  final String Function(String distance) toGo;
  final String passedStop;
  final String offTheWay;

  /// What the watch on the next connection says: hurry while walking to it,
  /// a change ahead that needs hurrying, or a ride that will be missed
  final String Function(String route, String left) hurryNow;
  final String Function(String route, String stop) hurryAhead;
  final String noLonger;
  final String Function(String route, String stop) missedRide;
  final String findAnother;
  final String planAgain;

  /// The switch that keeps a journey followed with the app off the screen
  final String followAway;
  final String followAwayHint;

  /// Names of the notification channels, as the phone's settings list them
  final String followChannel;
  final String alertChannel;
  final String arrived;
  final String Function(int metres) metres;
  final String Function(double km) km;
  final String Function(int minutes) walkLeg;
  final String Function(int changes) changeCount;
  final String Function(String stops) changeAt;
  final String Function(int backups) backupCount;
  final String Function(DateTime day) shortDay;
  final String Function(int minutes) minutes;
  final String Function(double kmh) kmh;
  final String Function(int option) alsoOption;
  final String Function(String server) unreachable;
}

const _en = Strings(
  signIn: 'Sign in',
  tagline: 'Where the buses actually are',
  inviteCode: 'Invite code',
  inviteHint: 'The last part of the link you were sent',
  username: 'Username',
  password: 'Password',
  passwordHint: 'At least 10 characters',
  changePassword: 'Change password',
  currentPassword: 'Current password',
  newPassword: 'New password',
  passwordChanged: 'Password changed - every other device is signed out',
  stayIn: 'Stay signed in',
  createAccount: 'Create the account',
  join: 'Join',
  haveAccount: 'I already have an account',
  wantAccount: 'Create an account',
  haveInvite: 'I have an invite code',
  map: 'Map',
  mine: 'Mine',
  lines: 'Lines',
  allLines: 'All',
  watchingLines: _enWatchingLines,
  nearLines: 'Near me',
  nothingNearLines: _enNothingNearLines,
  noneWatched: 'Nothing watched yet. Tap a route to watch it.',
  recentLines: 'Opened lately',
  otherWay: 'The other way',
  watchLine: 'Watch',
  noLineStops: 'The stops of this line are not known',
  vehicleHere: 'A vehicle heading here',
  mapStyle: 'Map style',
  themeNames: {
    'colorful-dark': 'Colorful dark',
    'natural-dark': 'Natural dark',
    'muted-dark': 'Muted dark',
    'gray-dark': 'Gray dark',
    'colorful': 'Colorful',
    'natural': 'Natural',
    'muted': 'Muted',
    'gray': 'Gray',
  },
  server: 'Server',
  signOut: 'Sign out',
  routes: 'Routes',
  kinds: {'bus': 'Buses', 'tram': 'Trams', 'trolleybus': 'Trolleybuses'},
  everyRoute: 'Every route',
  layers: 'Layers',
  attributions: 'Attributions',
  account: 'Account',
  findStop: 'Find a stop or a place',
  tryAgain: 'Try again',
  filterRoutes: 'Filter routes',
  clear: 'Clear',
  saveAsSet: 'Save as a set',
  updateSet: _enUpdateSet,
  nameSet: 'Name this set',
  rename: 'Rename',
  delete: 'Delete',
  places: 'Saved places',
  savePlace: 'Save this place',
  getHere: 'Get here',
  namePlace: 'Name this place',
  thisPlace: 'This place',
  savePlaceAs: 'Save this place...',
  placeNameTaken: 'A place with that name is already saved',
  placeMoved: _enPlaceMoved,
  toHere: 'Directions to here',
  fromHere: 'Directions from here',
  nearHere: 'Stops near here',
  nothingNearHere: 'No stop within 2 km of this place',
  noPlaces: 'Save a place and it is offered here',
  saved: 'Saved',
  pinnedStops: 'Pinned stops',
  saveHow: 'Save a place with the star in the search or by holding the map',
  holdToManage: 'Hold one to rename or remove it',
  foundStops: 'Stops',
  foundPlaces: 'Places',
  noSearch: 'Place search is unavailable',
  nearMe: 'Stops near me',
  nothingNear: 'No stop within 2 km of where you are',
  nothingFound: 'No stop or place by that name',
  traffic: 'Traffic',
  departAt: 'Leave at',
  preferBy: 'Order',
  quietPart: 'Nothing seen running',
  saveHere: 'Save',
  cancel: 'Cancel',
  save: 'Save',
  use: 'Use',
  sets: 'Sets',
  noSets: 'Watch some routes and save them as a set in the Lines tab',
  pin: 'Pin',
  unpin: 'Unpin',
  callsHere: 'Calls here',
  nothingDue: 'Nothing due here for now',
  pickARoute: 'Pick a route to see it moving',
  pinAStop: 'Pin a stop and its times show up here',
  language: 'Language',
  noBasemap: 'The basemap would not load',
  faceNorth: 'Face north',
  zoomIn: 'Zoom in',
  zoomOut: 'Zoom out',
  whereAmI: 'Where I am',
  noLocation: "Location is off or not allowed for the app - turn it on in the phone's settings",
  renewed: "The city's routes and timetables were updated",
  quietTitle: 'Possibly an air raid alert',
  quietDetail:
      'Few vehicles are reporting where they are, so positions and arrival '
      'times may be missing or off',
  plannerPreparing:
      'The journey planner is getting ready - try again in a few minutes',
  plan: 'Journey',
  from: 'From',
  to: 'To',
  tapMap: 'Tap the map',
  useHere: 'Where I am',
  swap: 'Swap',
  findRoute: 'Find a way',
  searching: 'Looking for a way',
  noJourney: 'No way to get there was found',
  report: 'Something looks wrong? Report it',
  reportNote:
      'What looks wrong? Optional. The search and the live data it ran on '
      'are sent with it.',
  reported: 'Reported, thank you',
  send: 'Send',
  toDoor: 'To the door',
  noChange: 'No changes',
  prefer: _enPrefer,
  schedulePart: 'Timetable',
  chooseOnMap: 'Choose on the map',
  hidePanel: 'Hide, keeping the journey on the map',
  showPanel: 'Show the journey',
  leaveOn: 'Leave on',
  paces: 'Walking and hurrying',
  pacesNow: _enPacesNow,
  walkSpeed: 'Walking speed',
  walkSpeedHint: 'On flat ground - hills are taken into account',
  hurrySpeed: 'Hurrying speed',
  hurrySpeedHint: 'How fast you would walk to catch a bus. Off, only a bus you would miss by seconds is offered as one to hurry for',
  hurry: 'Hurry',
  hurryHint: 'Only hurrying to the first stop catches this bus',
  hurryAt: _enHurryAt,
  paceHint: 'Walk at least this fast to be at the stop with time to spare, in case the bus comes early',
  slower: 'Slower',
  faster: 'Faster',
  alsoOptionHint: 'This way is also among the options',
  showWay: 'Show this way on the map',
  showLine: 'Show this line',
  lineOf: _enLineOf,
  watchRoute: 'Watch on the map',
  unwatchRoute: 'Stop watching',
  searchAgain: 'That search is no longer held; search again',
  today: 'Today',
  tomorrow: 'Tomorrow',
  backups: 'Backups',
  backupsWhy: 'Later ways from the same stop if you miss a ride, arriving within half an hour of the plan. Outlined: a vehicle already in your plan.',
  noBackup: 'None within half an hour',
  moreBackups: _enMoreBackups,
  scheduleWhy:
      'No vehicle tracked for this ride yet - the time is from the timetable',
  terminusPart: 'Next trip',
  terminusWhy: 'The vehicle has not set off on this trip yet - the time is estimated from when this line usually leaves its terminus',
  quietWhy: 'Timetabled, but nothing on this route has been seen for an hour. It may not be running.',
  wholeWalk: 'Walk the whole way',
  planHint:
      'Tap From or To to search, pick a saved place or choose on the map.',
  follow: 'Follow it',
  followHint:
      'Says what to do next as you travel. Where you are stays on this phone.',
  endFollow: 'End',
  locating: 'Finding where you are',
  walkTo: _enWalkTo,
  walkHome: 'Walk to the door',
  waitAt: _enWaitAt,
  showSteps: 'Show every step of the journey',
  hideSteps: 'Hide the steps',
  dueIn: _enDueIn,
  offAt: _enOffAt,
  offSoon: _enOffSoon,
  toGo: _enToGo,
  passedStop: 'You have passed your stop',
  offTheWay: 'You are off the planned way',
  hurryNow: _enHurryNow,
  hurryAhead: _enHurryAhead,
  noLonger: 'This journey no longer works',
  missedRide: _enMissedRide,
  findAnother: 'Find another way',
  planAgain: 'Search again',
  followAway: 'Follow with the app closed',
  followAwayHint: 'Follows with the screen off and shows the next step in a notification. Your location stays on this phone.',
  followChannel: 'Journey being followed',
  alertChannel: 'When to get off',
  arrived: 'You have arrived',
  metres: _enMetres,
  km: _enKm,
  walkLeg: _enWalkLeg,
  changeCount: _enChangeCount,
  changeAt: _enChangeAt,
  backupCount: _enBackupCount,
  shortDay: _enShortDay,
  stopsAhead: 'Stops ahead',
  vehicleGone: 'This one is no longer being tracked',
  onIt: "I'm on it",
  onItHint: 'Plan a journey starting on board this vehicle',
  aboard: 'On board',
  now: 'Now',
  oneMinute: '1 min',
  minutes: _enMinutes,
  kmh: _enKmh,
  alsoOption: _enAlsoOption,
  unreachable: _enUnreachable,
);

String _enUpdateSet(String name) => 'Update “$name”';
String _enPlaceMoved(String name) => '“$name” moved here';
String _enWatchingLines(int n) => 'Watching $n';
String _enNothingNearLines(int metres) =>
    'No stop within $metres m of where you are';
String _enWalkLeg(int m) => 'Walk $m min';
String _enChangeCount(int n) => n == 1 ? '1 change' : '$n changes';
String _enChangeAt(String stops) => 'Change at $stops';
String _enBackupCount(int n) => n == 1 ? '1 backup' : '$n backups';
String _enMoreBackups(int n) => '$n more';
String _enShortDay(DateTime d) =>
    '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]} '
    '${d.day} '
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

String _enPrefer(Prefer p) => switch (p) {
  Prefer.fastest => 'Fastest',
  Prefer.walk => 'Less walking',
  Prefer.changes => 'Fewer changes',
  Prefer.reliable => 'Most backups',
};
String _enMinutes(int m) => '$m min';
String _enKmh(double v) => '${v.toStringAsFixed(1)} km/h';
String _enPacesNow(double walk, double? hurry) =>
    '${_enKmh(walk)}, ${hurry == null ? 'not hurrying' : 'hurrying ${_enKmh(hurry)}'}';

String _enHurryAt(String pace) => 'Hurry: $pace';
String _enAlsoOption(int n) => 'Option $n';
String _enLineOf(String route) => 'Line $route';
String _enUnreachable(String server) => 'Could not reach $server';
String _enWalkTo(String stop) => 'Walk to $stop';
String _enWaitAt(String stop) => 'Wait at $stop';
String _enDueIn(String when) => 'Due: $when';
String _enOffAt(String stop) => 'Get off at $stop';
String _enOffSoon(String stop) => 'Get ready to get off at $stop';
String _enHurryNow(String route, String left) =>
    'Hurry: $route leaves in $left';
String _enHurryAhead(String route, String stop) =>
    '$route at $stop is caught only by hurrying';
String _enMissedRide(String route, String stop) =>
    '$route at $stop will be missed';
String _enToGo(String distance) => '$distance to go';
String _enMetres(int m) => '$m m';
String _enKm(double km) => '${km.toStringAsFixed(1)} km';

const _uk = Strings(
  signIn: 'Увійти',
  tagline: 'Де насправді їде транспорт',
  inviteCode: 'Код запрошення',
  inviteHint: 'Остання частина надісланого посилання',
  username: 'Імʼя',
  password: 'Пароль',
  passwordHint: 'Щонайменше 10 символів',
  changePassword: 'Змінити пароль',
  currentPassword: 'Поточний пароль',
  newPassword: 'Новий пароль',
  passwordChanged: 'Пароль змінено - на всіх інших пристроях виконано вихід',
  stayIn: 'Не виходити',
  createAccount: 'Створити акаунт',
  join: 'Приєднатися',
  haveAccount: 'У мене вже є акаунт',
  wantAccount: 'Створити акаунт',
  haveInvite: 'У мене є код запрошення',
  map: 'Мапа',
  mine: 'Моє',
  lines: 'Лінії',
  allLines: 'Усі',
  watchingLines: _ukWatchingLines,
  nearLines: 'Поруч',
  nothingNearLines: _ukNothingNearLines,
  noneWatched: 'Поки нічого не відстежується. Торкніться маршруту, щоб відстежувати його.',
  recentLines: 'Нещодавно відкриті',
  otherWay: 'Інший напрямок',
  watchLine: 'Відстежувати',
  noLineStops: 'Зупинки цієї лінії невідомі',
  vehicleHere: 'Транспорт прямує сюди',
  mapStyle: 'Вигляд мапи',
  themeNames: {
    'colorful-dark': 'Кольорова темна',
    'natural-dark': 'Природна темна',
    'muted-dark': 'Приглушена темна',
    'gray-dark': 'Сіра темна',
    'colorful': 'Кольорова',
    'natural': 'Природна',
    'muted': 'Приглушена',
    'gray': 'Сіра',
  },
  server: 'Сервер',
  signOut: 'Вийти',
  routes: 'Маршрути',
  kinds: {'bus': 'Автобуси', 'tram': 'Трамваї', 'trolleybus': 'Тролейбуси'},
  everyRoute: 'Усі маршрути',
  layers: 'Шари',
  attributions: 'Джерела мапи',
  account: 'Обліковий запис',
  findStop: 'Зупинка або місце',
  tryAgain: 'Спробувати ще',
  filterRoutes: 'Пошук маршруту',
  clear: 'Очистити',
  saveAsSet: 'Зберегти як набір',
  updateSet: _ukUpdateSet,
  nameSet: 'Назва набору',
  rename: 'Перейменувати',
  delete: 'Видалити',
  places: 'Збережені місця',
  savePlace: 'Зберегти це місце',
  getHere: 'Маршрут сюди',
  namePlace: 'Назва місця',
  thisPlace: 'Це місце',
  savePlaceAs: 'Зберегти це місце...',
  placeNameTaken: 'Місце з такою назвою вже збережено',
  placeMoved: _ukPlaceMoved,
  toHere: 'Маршрут сюди',
  fromHere: 'Маршрут звідси',
  nearHere: 'Зупинки поблизу',
  nothingNearHere: 'Немає зупинки ближче ніж за 2 км звідси',
  noPlaces: 'Збережене місце зʼявиться тут',
  saved: 'Збережене',
  pinnedStops: 'Закріплені зупинки',
  saveHow: 'Збережіть місце зірочкою в пошуку або утримавши мапу',
  holdToManage: 'Утримуйте, щоб перейменувати або видалити',
  foundStops: 'Зупинки',
  foundPlaces: 'Місця',
  noSearch: 'Пошук місць недоступний',
  nearMe: 'Зупинки поруч',
  nothingNear: 'Немає зупинки ближче ніж за 2 км',
  nothingFound: 'Немає зупинки чи місця з такою назвою',
  traffic: 'Затори',
  departAt: 'Виїзд о',
  preferBy: 'Порядок',
  quietPart: 'Рейсів не видно',
  saveHere: 'Зберегти',
  cancel: 'Скасувати',
  save: 'Зберегти',
  use: 'Використати',
  sets: 'Набори',
  noSets:
      'Відстежуйте кілька маршрутів і збережіть їх як набір у вкладці Лінії',
  pin: 'Закріпити',
  unpin: 'Відкріпити',
  callsHere: 'Тут зупиняються',
  nothingDue: 'Поки що сюди нічого не їде',
  pickARoute: 'Оберіть маршрут, щоб побачити рух',
  pinAStop: 'Закріпіть зупинку - і час буде тут',
  language: 'Мова',
  noBasemap: 'Не вдалося завантажити мапу',
  faceNorth: 'На північ',
  zoomIn: 'Наблизити',
  zoomOut: 'Віддалити',
  whereAmI: 'Де я',
  noLocation: 'Геолокацію вимкнено або не дозволено застосунку - увімкніть її в налаштуваннях телефона',
  renewed: 'Маршрути й розклади міста оновилися',
  quietTitle: 'Можливо, повітряна тривога',
  quietDetail:
      'Мало транспорту передає, де він є, тож розташування й час прибуття '
      'можуть бути неповні або неточні',
  plannerPreparing:
      'Планувальник поїздок готується - спробуйте за кілька хвилин',
  plan: 'Поїздка',
  from: 'Звідки',
  to: 'Куди',
  tapMap: 'Торкніться мапи',
  useHere: 'Де я',
  swap: 'Поміняти',
  findRoute: 'Знайти шлях',
  searching: 'Шукаємо шлях',
  noJourney: 'Шляху не знайдено',
  report: 'Щось не так? Повідомити',
  reportNote:
      "Що не так? Необов'язково. Разом із цим надсилається пошук і живі дані, "
      'за якими його зроблено.',
  reported: 'Надіслано, дякуємо',
  send: 'Надіслати',
  toDoor: 'До місця',
  noChange: 'Без пересадок',
  prefer: _ukPrefer,
  schedulePart: 'За розкладом',
  chooseOnMap: 'Вибрати на мапі',
  hidePanel: 'Сховати, лишивши маршрут на мапі',
  showPanel: 'Показати маршрут',
  leaveOn: 'Виїзд',
  paces: 'Ходьба і поспіх',
  pacesNow: _ukPacesNow,
  walkSpeed: 'Швидкість ходьби',
  walkSpeedHint: 'По рівному - схили враховано',
  hurrySpeed: 'Швидкість, коли поспішаєте',
  hurrySpeedHint: 'Як швидко ви йшли б, щоб встигнути на автобус. Вимкнено - пропонуємо поспішити лише на той, що ви пропустили б на секунди',
  hurry: 'Поспішіть',
  hurryHint: 'На цей автобус встигнете, лише якщо поспішите до першої зупинки',
  hurryAt: _ukHurryAt,
  paceHint: 'Ідіть щонайменше так швидко, щоб бути на зупинці із запасом, якщо автобус прийде раніше',
  slower: 'Повільніше',
  faster: 'Швидше',
  alsoOptionHint: 'Цей шлях є і серед варіантів',
  showWay: 'Показати цей шлях на мапі',
  showLine: 'Показати лінію',
  lineOf: _ukLineOf,
  watchRoute: 'Стежити на мапі',
  unwatchRoute: 'Не стежити',
  searchAgain: 'Цей пошук уже не збережено; шукайте знову',
  today: 'Сьогодні',
  tomorrow: 'Завтра',
  backups: 'Запасні',
  backupsWhy: 'Пізніші способи з тієї ж зупинки, якщо ви пропустили рейс, з прибуттям щонайбільше на пів години пізніше. У рамці - транспорт, який уже є у вашому плані.',
  noBackup: 'Жодного за пів години',
  moreBackups: _ukMoreBackups,
  scheduleWhy:
      'Для цієї поїздки ще не відстежується транспорт - час із розкладу',
  terminusPart: 'Наступний рейс',
  terminusWhy: 'Транспорт ще не вирушив у цей рейс - час оцінено за тим, коли ця лінія зазвичай рушає з кінцевої',
  quietWhy: 'За розкладом курсує, але транспорту цього маршруту не видно вже годину. Можливо, він не їздить.',
  wholeWalk: 'Пішки весь шлях',
  planHint: 'Торкніться «Звідки» чи «Куди», щоб шукати, вибрати збережене місце або вказати на мапі.',
  follow: 'Вести',
  followHint: 'Підказує, що робити далі, поки ви в дорозі. Де ви є, лишається на цьому телефоні.',
  endFollow: 'Завершити',
  locating: 'Визначаємо, де ви',
  walkTo: _ukWalkTo,
  walkHome: 'Ідіть до місця призначення',
  waitAt: _ukWaitAt,
  showSteps: 'Показати всі кроки поїздки',
  hideSteps: 'Сховати кроки',
  dueIn: _ukDueIn,
  offAt: _ukOffAt,
  offSoon: _ukOffSoon,
  toGo: _ukToGo,
  passedStop: 'Ви проїхали свою зупинку',
  offTheWay: 'Ви зійшли з запланованого шляху',
  hurryNow: _ukHurryNow,
  hurryAhead: _ukHurryAhead,
  noLonger: 'Цей шлях більше не працює',
  missedRide: _ukMissedRide,
  findAnother: 'Знайти інший шлях',
  planAgain: 'Шукати знову',
  followAway: 'Супровід із закритим застосунком',
  followAwayHint: 'Супроводжує з вимкненим екраном і показує наступний крок у сповіщенні. Де ви є, лишається на цьому телефоні.',
  followChannel: 'Поїздка, яку супроводжують',
  alertChannel: 'Коли виходити',
  arrived: 'Ви на місці',
  metres: _ukMetres,
  km: _ukKm,
  walkLeg: _ukWalkLeg,
  changeCount: _ukChangeCount,
  changeAt: _ukChangeAt,
  backupCount: _ukBackupCount,
  shortDay: _ukShortDay,
  stopsAhead: 'Наступні зупинки',
  vehicleGone: 'Цей транспорт більше не відстежується',
  onIt: 'Я в ньому',
  onItHint: 'Спланувати поїздку, починаючи в цьому транспорті',
  aboard: 'У транспорті',
  now: 'Зараз',
  oneMinute: '1 хв',
  minutes: _ukMinutes,
  kmh: _ukKmh,
  alsoOption: _ukAlsoOption,
  unreachable: _ukUnreachable,
);

String _ukUpdateSet(String name) => 'Оновити «$name»';
String _ukPlaceMoved(String name) => '«$name» перенесено сюди';
String _ukWatchingLines(int n) => 'Відстежую $n';
String _ukNothingNearLines(int metres) =>
    'Немає зупинки ближче ніж за $metres м';
String _ukWalkLeg(int m) => 'Пішки $m хв';
String _ukChangeCount(int n) => n == 1 ? '1 пересадка' : 'Пересадок: $n';
String _ukChangeAt(String stops) => 'Пересадка: $stops';
String _ukBackupCount(int n) => n == 1 ? '1 запасний' : 'Запасних: $n';
String _ukMoreBackups(int n) => 'Ще $n';
String _ukShortDay(DateTime d) =>
    '${const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'][d.weekday - 1]} '
    '${d.day} '
    '${const ['січ.', 'лют.', 'бер.', 'квіт.', 'трав.', 'черв.', 'лип.', 'серп.', 'вер.', 'жовт.', 'лист.', 'груд.'][d.month - 1]}';

String _ukPrefer(Prefer p) => switch (p) {
  Prefer.fastest => 'Швидше',
  Prefer.walk => 'Менше пішки',
  Prefer.changes => 'Менше пересадок',
  Prefer.reliable => 'Більше запасних',
};
String _ukMinutes(int m) => '$m хв';
String _ukKmh(double v) =>
    '${v.toStringAsFixed(1).replaceAll('.', ',')} км/год';
String _ukPacesNow(double walk, double? hurry) =>
    '${_ukKmh(walk)}, ${hurry == null ? 'без поспіху' : 'поспіх ${_ukKmh(hurry)}'}';

String _ukHurryAt(String pace) => 'Поспішіть: $pace';
String _ukAlsoOption(int n) => 'Варіант $n';
String _ukLineOf(String route) => 'Лінія $route';
String _ukUnreachable(String server) => 'Не вдалося зʼєднатися з $server';
String _ukWalkTo(String stop) => 'Ідіть до зупинки $stop';
String _ukWaitAt(String stop) => 'Чекайте на зупинці $stop';
String _ukDueIn(String when) => 'Прибуде: $when';
String _ukOffAt(String stop) => 'Виходьте на зупинці $stop';
String _ukOffSoon(String stop) => 'Готуйтеся виходити на зупинці $stop';
String _ukHurryNow(String route, String left) =>
    'Поспішіть: $route відходить через $left';
String _ukHurryAhead(String route, String stop) =>
    'На $route на зупинці $stop встигнете, лише якщо поспішите';
String _ukMissedRide(String route, String stop) =>
    'На $route на зупинці $stop не встигнете';
String _ukToGo(String distance) => 'Ще $distance';
String _ukMetres(int m) => '$m м';
String _ukKm(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')} км';

/// Set from `main` before anything is drawn, and again from the picker.
Lang lang = Lang.uk;
Strings txt = _uk;

/// What `main` listens to, to rebuild the tree from the root once.
final langChanged = ValueNotifier(lang);

void useLang(Lang next) {
  lang = next;
  txt = next == Lang.uk ? _uk : _en;
  langChanged.value = next;
}

Lang phoneLang() =>
    PlatformDispatcher.instance.locales.any((l) => l.languageCode == 'uk')
    ? Lang.uk
    : Lang.en;
