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
    required this.renewed,
    required this.plannerPreparing,
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
    required this.walkSpeed,
    required this.walkSpeedHint,
    required this.slower,
    required this.faster,
    required this.alsoOptionHint,
    required this.today,
    required this.tomorrow,
    required this.backups,
    required this.backupsWhy,
    required this.noBackup,
    required this.moreBackups,
    required this.scheduleWhy,
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
    required this.dueIn,
    required this.offAt,
    required this.offSoon,
    required this.toGo,
    required this.passedStop,
    required this.offTheWay,
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

  /// The service moved to new routes and timetables while the app was open.
  final String renewed;
  final String plannerPreparing;
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
  final String walkSpeed;
  final String walkSpeedHint;
  final String slower;
  final String faster;
  final String alsoOptionHint;
  final String today;
  final String tomorrow;
  final String backups;
  final String backupsWhy;
  final String noBackup;
  final String Function(int more) moreBackups;
  final String scheduleWhy;
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
  final String Function(String when) dueIn;
  final String Function(String stop) offAt;
  final String Function(String stop) offSoon;
  final String Function(String distance) toGo;
  final String passedStop;
  final String offTheWay;

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
  renewed: "The city's routes and timetables were updated",
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
  walkSpeed: 'Walking speed',
  walkSpeedHint: 'On flat ground - hills are taken into account',
  slower: 'Slower',
  faster: 'Faster',
  alsoOptionHint: 'This way is also among the options',
  today: 'Today',
  tomorrow: 'Tomorrow',
  backups: 'Backups',
  backupsWhy: 'Later ways from the same stop if you miss a ride, arriving within half an hour of the plan. Outlined: a vehicle already in your plan.',
  noBackup: 'None within half an hour',
  moreBackups: _enMoreBackups,
  scheduleWhy:
      'No vehicle tracked for this ride yet - the time is from the timetable',
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
  dueIn: _enDueIn,
  offAt: _enOffAt,
  offSoon: _enOffSoon,
  toGo: _enToGo,
  passedStop: 'You have passed your stop',
  offTheWay: 'You are off the planned way',
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
  now: 'Now',
  oneMinute: '1 min',
  minutes: _enMinutes,
  kmh: _enKmh,
  alsoOption: _enAlsoOption,
  unreachable: _enUnreachable,
);

String _enUpdateSet(String name) => 'Update “$name”';
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
String _enAlsoOption(int n) => 'Option $n';
String _enUnreachable(String server) => 'Could not reach $server';
String _enWalkTo(String stop) => 'Walk to $stop';
String _enWaitAt(String stop) => 'Wait at $stop';
String _enDueIn(String when) => 'Due: $when';
String _enOffAt(String stop) => 'Get off at $stop';
String _enOffSoon(String stop) => 'Get ready to get off at $stop';
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
  renewed: 'Маршрути й розклади міста оновилися',
  plannerPreparing:
      'Планувальник поїздок готується - спробуйте за кілька хвилин',
  plan: 'Маршрут',
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
  walkSpeed: 'Швидкість ходьби',
  walkSpeedHint: 'По рівному - схили враховано',
  slower: 'Повільніше',
  faster: 'Швидше',
  alsoOptionHint: 'Цей шлях є і серед варіантів',
  today: 'Сьогодні',
  tomorrow: 'Завтра',
  backups: 'Запасні',
  backupsWhy: 'Пізніші способи з тієї ж зупинки, якщо ви пропустили рейс, з прибуттям щонайбільше на пів години пізніше. У рамці - транспорт, який уже є у вашому плані.',
  noBackup: 'Жодного за пів години',
  moreBackups: _ukMoreBackups,
  scheduleWhy:
      'Для цієї поїздки ще не відстежується транспорт - час із розкладу',
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
  dueIn: _ukDueIn,
  offAt: _ukOffAt,
  offSoon: _ukOffSoon,
  toGo: _ukToGo,
  passedStop: 'Ви проїхали свою зупинку',
  offTheWay: 'Ви зійшли з запланованого шляху',
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
  now: 'Зараз',
  oneMinute: '1 хв',
  minutes: _ukMinutes,
  kmh: _ukKmh,
  alsoOption: _ukAlsoOption,
  unreachable: _ukUnreachable,
);

String _ukUpdateSet(String name) => 'Оновити «$name»';
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
String _ukAlsoOption(int n) => 'Варіант $n';
String _ukUnreachable(String server) => 'Не вдалося зʼєднатися з $server';
String _ukWalkTo(String stop) => 'Ідіть до зупинки $stop';
String _ukWaitAt(String stop) => 'Чекайте на зупинці $stop';
String _ukDueIn(String when) => 'Прибуде: $when';
String _ukOffAt(String stop) => 'Виходьте на зупинці $stop';
String _ukOffSoon(String stop) => 'Готуйтеся виходити на зупинці $stop';
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
