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
    required this.stayIn,
    required this.createAccount,
    required this.join,
    required this.haveAccount,
    required this.wantAccount,
    required this.haveInvite,
    required this.map,
    required this.times,
    required this.mapStyle,
    required this.server,
    required this.signOut,
    required this.routes,
    required this.routeLine,
    required this.showRoute,
    required this.everyRoute,
    required this.layers,
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
    required this.holdForLine,
    required this.places,
    required this.savePlace,
    required this.namePlace,
    required this.noPlaces,
    required this.saved,
    required this.pinnedStops,
    required this.nothingSaved,
    required this.showOnMap,
    required this.holdToManage,
    required this.foundStops,
    required this.foundPlaces,
    required this.noSearch,
    required this.traffic,
    required this.departAt,
    required this.preferBy,
    required this.quietPart,
    required this.forget,
    required this.saveHere,
    required this.cancel,
    required this.save,
    required this.use,
    required this.sets,
    required this.pin,
    required this.unpin,
    required this.callsHere,
    required this.nothingDueWatched,
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
    required this.stopsAhead,
    required this.vehicleGone,
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
    required this.toDoor,
    required this.noChange,
    required this.prefer,
    required this.livePart,
    required this.schedulePart,
    required this.wholeWalk,
    required this.planHint,
    required this.walkLeg,
    required this.changeCount,
    required this.backupCount,
    required this.minutes,
    required this.unreachable,
  });

  final String signIn;
  final String tagline;
  final String inviteCode;
  final String inviteHint;
  final String username;
  final String password;
  final String stayIn;
  final String createAccount;
  final String join;
  final String haveAccount;
  final String wantAccount;
  final String haveInvite;
  final String map;
  final String times;
  final String mapStyle;
  final String server;
  final String signOut;
  final String routes;

  /// A second word for "route": Ukrainian already spends one on `plan`.
  final String routeLine;
  final String showRoute;
  final String everyRoute;
  final String layers;
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
  final String holdForLine;
  final String places;
  final String savePlace;
  final String namePlace;
  final String noPlaces;
  final String saved;
  final String pinnedStops;
  final String nothingSaved;
  final String showOnMap;
  final String holdToManage;
  final String foundStops;
  final String foundPlaces;
  final String noSearch;
  final String traffic;
  final String departAt;
  final String preferBy;

  /// The timetable on a line nothing has been seen running on.
  final String quietPart;
  final String forget;
  final String saveHere;
  final String cancel;
  final String save;
  final String use;
  final String sets;
  final String pin;
  final String unpin;
  final String callsHere;
  final String nothingDueWatched;
  final String nothingDue;
  final String pickARoute;
  final String pinAStop;
  final String language;
  final String noBasemap;
  final String faceNorth;
  final String zoomIn;
  final String zoomOut;
  final String whereAmI;
  final String noLocation;
  final String stopsAhead;
  final String vehicleGone;
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
  final String toDoor;
  final String noChange;
  final String Function(Prefer p) prefer;
  final String livePart;
  final String schedulePart;
  final String wholeWalk;
  final String planHint;
  final String Function(int minutes) walkLeg;
  final String Function(int changes) changeCount;
  final String Function(int backups) backupCount;
  final String Function(int minutes) minutes;
  final String Function(String server) unreachable;
}

const _en = Strings(
  signIn: 'Sign in',
  tagline: 'Where the buses actually are',
  inviteCode: 'Invite code',
  inviteHint: 'The last part of the link you were sent',
  username: 'Username',
  password: 'Password',
  stayIn: 'Stay signed in',
  createAccount: 'Create the account',
  join: 'Join',
  haveAccount: 'I already have an account',
  wantAccount: 'Create an account',
  haveInvite: 'I have an invite code',
  map: 'Map',
  times: 'Times',
  mapStyle: 'Map style',
  server: 'Server',
  signOut: 'Sign out',
  routes: 'Routes',
  routeLine: 'Line',
  showRoute: 'Show this route on the map',
  everyRoute: 'Every route',
  layers: 'Layers',
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
  holdForLine: 'Hold a route to see its line',
  places: 'Saved places',
  savePlace: 'Save this place',
  namePlace: 'Name this place',
  noPlaces: 'Save a place and it is offered here',
  saved: 'Saved',
  pinnedStops: 'Pinned stops',
  nothingSaved: 'Nothing saved yet',
  showOnMap: 'Tap a row to show it on the map',
  holdToManage: 'Hold one to rename or remove it',
  foundStops: 'Stops',
  foundPlaces: 'Places',
  noSearch: 'Place search is unavailable',
  traffic: 'Traffic',
  departAt: 'Leave at',
  preferBy: 'Order',
  quietPart: 'Nothing seen running',
  forget: 'Forget',
  saveHere: 'Save',
  cancel: 'Cancel',
  save: 'Save',
  use: 'Use',
  sets: 'Sets',
  pin: 'Pin',
  unpin: 'Unpin',
  callsHere: 'Calls here',
  nothingDueWatched: 'Nothing due on the routes you are watching',
  nothingDue: 'Nothing due',
  pickARoute: 'Pick a route to see it moving',
  pinAStop: 'Pin a stop and its times show up here',
  language: 'Language',
  noBasemap: 'The basemap would not load',
  faceNorth: 'Face north',
  zoomIn: 'Zoom in',
  zoomOut: 'Zoom out',
  whereAmI: 'Where I am',
  noLocation: 'Location is not available',
  plan: 'Journey',
  from: 'From',
  to: 'To',
  tapMap: 'Tap the map',
  useHere: 'Where I am',
  swap: 'Swap',
  findRoute: 'Find a way',
  searching: 'Looking for a way',
  noJourney: 'No way to get there was found',
  toDoor: 'To the door',
  noChange: 'No changes',
  prefer: _enPrefer,
  livePart: 'Tracked',
  schedulePart: 'Timetable',
  wholeWalk: 'Walk the whole way',
  planHint: 'Tap the map to set where you are and where you are going.',
  walkLeg: _enWalkLeg,
  changeCount: _enChangeCount,
  backupCount: _enBackupCount,
  stopsAhead: 'Stops ahead',
  vehicleGone: 'This one is no longer being tracked',
  now: 'Now',
  oneMinute: '1 min',
  minutes: _enMinutes,
  unreachable: _enUnreachable,
);

String _enUpdateSet(String name) => 'Update “$name”';
String _enWalkLeg(int m) => 'Walk $m min';
String _enChangeCount(int n) => n == 1 ? '1 change' : '$n changes';
String _enBackupCount(int n) => n == 1 ? '1 backup' : '$n backups';

String _enPrefer(Prefer p) => switch (p) {
  Prefer.fastest => 'Fastest',
  Prefer.walk => 'Less walking',
  Prefer.changes => 'Fewer changes',
  Prefer.reliable => 'Most backups',
};
String _enMinutes(int m) => '$m min';
String _enUnreachable(String server) => 'Could not reach $server';

const _uk = Strings(
  signIn: 'Увійти',
  tagline: 'Де насправді їде транспорт',
  inviteCode: 'Код запрошення',
  inviteHint: 'Остання частина надісланого посилання',
  username: 'Імʼя',
  password: 'Пароль',
  stayIn: 'Не виходити',
  createAccount: 'Створити акаунт',
  join: 'Приєднатися',
  haveAccount: 'У мене вже є акаунт',
  wantAccount: 'Створити акаунт',
  haveInvite: 'У мене є код запрошення',
  map: 'Мапа',
  times: 'Час',
  mapStyle: 'Вигляд мапи',
  server: 'Сервер',
  signOut: 'Вийти',
  routes: 'Маршрути',
  routeLine: 'Лінія',
  showRoute: 'Показати цей маршрут на мапі',
  everyRoute: 'Усі маршрути',
  layers: 'Шари',
  account: 'Обліковий запис',
  findStop: 'Знайти зупинку або місце',
  tryAgain: 'Спробувати ще',
  filterRoutes: 'Пошук маршруту',
  clear: 'Очистити',
  saveAsSet: 'Зберегти як набір',
  updateSet: _ukUpdateSet,
  nameSet: 'Назва набору',
  rename: 'Перейменувати',
  delete: 'Видалити',
  holdForLine: 'Утримуйте маршрут, щоб побачити лінію',
  places: 'Збережені місця',
  savePlace: 'Зберегти це місце',
  namePlace: 'Назва місця',
  noPlaces: 'Збережене місце зʼявиться тут',
  saved: 'Збережене',
  pinnedStops: 'Закріплені зупинки',
  nothingSaved: 'Поки нічого не збережено',
  showOnMap: 'Торкніться рядка, щоб показати на мапі',
  holdToManage: 'Утримуйте, щоб перейменувати або видалити',
  foundStops: 'Зупинки',
  foundPlaces: 'Місця',
  noSearch: 'Пошук місць недоступний',
  traffic: 'Затори',
  departAt: 'Виїзд о',
  preferBy: 'Порядок',
  quietPart: 'Рейсів не видно',
  forget: 'Забути',
  saveHere: 'Зберегти',
  cancel: 'Скасувати',
  save: 'Зберегти',
  use: 'Використати',
  sets: 'Набори',
  pin: 'Закріпити',
  unpin: 'Відкріпити',
  callsHere: 'Тут зупиняються',
  nothingDueWatched: 'На обраних маршрутах нічого не їде',
  nothingDue: 'Нічого не їде',
  pickARoute: 'Оберіть маршрут, щоб побачити рух',
  pinAStop: 'Закріпіть зупинку - і час буде тут',
  language: 'Мова',
  noBasemap: 'Не вдалося завантажити мапу',
  faceNorth: 'На північ',
  zoomIn: 'Наблизити',
  zoomOut: 'Віддалити',
  whereAmI: 'Де я',
  noLocation: 'Місцеперебування недоступне',
  plan: 'Маршрут',
  from: 'Звідки',
  to: 'Куди',
  tapMap: 'Торкніться мапи',
  useHere: 'Де я',
  swap: 'Поміняти',
  findRoute: 'Знайти шлях',
  searching: 'Шукаємо шлях',
  noJourney: 'Шляху не знайдено',
  toDoor: 'До місця',
  noChange: 'Без пересадок',
  prefer: _ukPrefer,
  livePart: 'За відстеженням',
  schedulePart: 'За розкладом',
  wholeWalk: 'Пішки весь шлях',
  planHint: 'Торкніться мапи, щоб вказати, де ви є і куди прямуєте.',
  walkLeg: _ukWalkLeg,
  changeCount: _ukChangeCount,
  backupCount: _ukBackupCount,
  stopsAhead: 'Наступні зупинки',
  vehicleGone: 'Цей транспорт більше не відстежується',
  now: 'Зараз',
  oneMinute: '1 хв',
  minutes: _ukMinutes,
  unreachable: _ukUnreachable,
);

String _ukUpdateSet(String name) => 'Оновити «$name»';
String _ukWalkLeg(int m) => 'Пішки $m хв';
String _ukChangeCount(int n) => n == 1 ? '1 пересадка' : 'Пересадок: $n';
String _ukBackupCount(int n) => n == 1 ? '1 запасний' : 'Запасних: $n';

String _ukPrefer(Prefer p) => switch (p) {
  Prefer.fastest => 'Швидше',
  Prefer.walk => 'Менше пішки',
  Prefer.changes => 'Менше пересадок',
  Prefer.reliable => 'Більше запасних',
};
String _ukMinutes(int m) => '$m хв';
String _ukUnreachable(String server) => 'Не вдалося зʼєднатися з $server';

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
