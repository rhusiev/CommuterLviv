/// Ukrainian and English, chosen once at launch.
///
/// A port of `web/src/lib/i18n.ts`, key for key, so the two clients say the
/// same things. Flutter's own `intl` machinery generates a class per locale
/// from ARB files; two locales and sixty strings do not pay for the build step,
/// and this way the strings can be read without a code generator having run.
///
/// `txt` is a top-level value rather than an inherited widget, so changing the
/// language takes a restart. The picker says so. It is not called `s` because
/// half the widgets here already call a stop that.
library;

import 'dart:ui' show PlatformDispatcher;

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
    required this.findStop,
    required this.tryAgain,
    required this.filterRoutes,
    required this.clear,
    required this.saveAsSet,
    required this.nameSet,
    required this.cancel,
    required this.save,
    required this.use,
    required this.sets,
    required this.dark,
    required this.light,
    required this.pin,
    required this.unpin,
    required this.callsHere,
    required this.nothingDueWatched,
    required this.nothingDue,
    required this.pickARoute,
    required this.pinAStop,
    required this.language,
    required this.restartToApply,
    required this.noBasemap,
    required this.faceNorth,
    required this.zoomIn,
    required this.zoomOut,
    required this.whereAmI,
    required this.noLocation,
    required this.now,
    required this.oneMinute,
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
  final String findStop;
  final String tryAgain;
  final String filterRoutes;
  final String clear;
  final String saveAsSet;
  final String nameSet;
  final String cancel;
  final String save;
  final String use;
  final String sets;
  final String dark;
  final String light;
  final String pin;
  final String unpin;
  final String callsHere;
  final String nothingDueWatched;
  final String nothingDue;
  final String pickARoute;
  final String pinAStop;
  final String language;
  final String restartToApply;
  final String noBasemap;
  final String faceNorth;
  final String zoomIn;
  final String zoomOut;
  final String whereAmI;
  final String noLocation;
  final String now;
  final String oneMinute;
  final String Function(int minutes) minutes;
  final String Function(String server) unreachable;
}

const _en = Strings(
  signIn: 'Sign in',
  tagline: 'where the buses actually are',
  inviteCode: 'Invite code',
  inviteHint: 'the last part of the link you were sent',
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
  findStop: 'Find a stop',
  tryAgain: 'Try again',
  filterRoutes: 'Filter routes',
  clear: 'Clear',
  saveAsSet: 'Save as a set',
  nameSet: 'Name this set',
  cancel: 'Cancel',
  save: 'Save',
  use: 'Use',
  sets: 'Sets',
  dark: 'dark',
  light: 'light',
  pin: 'Pin',
  unpin: 'Unpin',
  callsHere: 'Calls here',
  nothingDueWatched: 'nothing due on the routes you are watching',
  nothingDue: 'nothing due',
  pickARoute: 'Pick a route to see it moving',
  pinAStop: 'Pin a stop and its times show up here',
  language: 'Language',
  restartToApply: 'the app has to be reopened',
  noBasemap: 'the basemap would not load',
  faceNorth: 'Face north',
  zoomIn: 'Zoom in',
  zoomOut: 'Zoom out',
  whereAmI: 'Where I am',
  noLocation: 'Location is not available',
  now: 'now',
  oneMinute: '1 min',
  minutes: _enMinutes,
  unreachable: _enUnreachable,
);

String _enMinutes(int m) => '$m min';
String _enUnreachable(String server) => 'could not reach $server';

const _uk = Strings(
  signIn: 'Увійти',
  tagline: 'де насправді їде транспорт',
  inviteCode: 'Код запрошення',
  inviteHint: 'остання частина надісланого посилання',
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
  findStop: 'Знайти зупинку',
  tryAgain: 'Спробувати ще',
  filterRoutes: 'Пошук маршруту',
  clear: 'Очистити',
  saveAsSet: 'Зберегти як набір',
  nameSet: 'Назва набору',
  cancel: 'Скасувати',
  save: 'Зберегти',
  use: 'Використати',
  sets: 'Набори',
  dark: 'темна',
  light: 'світла',
  pin: 'Закріпити',
  unpin: 'Відкріпити',
  callsHere: 'Тут зупиняються',
  nothingDueWatched: 'на обраних маршрутах нічого не їде',
  nothingDue: 'нічого не їде',
  pickARoute: 'Оберіть маршрут, щоб побачити рух',
  pinAStop: 'Закріпіть зупинку - і час буде тут',
  language: 'Мова',
  restartToApply: 'потрібно перезапустити застосунок',
  noBasemap: 'не вдалося завантажити мапу',
  faceNorth: 'На північ',
  zoomIn: 'Наблизити',
  zoomOut: 'Віддалити',
  whereAmI: 'Де я',
  noLocation: 'Місцеперебування недоступне',
  now: 'зараз',
  oneMinute: '1 хв',
  minutes: _ukMinutes,
  unreachable: _ukUnreachable,
);

String _ukMinutes(int m) => '$m хв';
String _ukUnreachable(String server) => 'не вдалося зʼєднатися з $server';

/// The language for this run: what was chosen before, else Ukrainian for a
/// phone set to it. Set from `main` before anything is drawn.
Lang lang = Lang.uk;
Strings txt = _uk;

void useLang(Lang next) {
  lang = next;
  txt = next == Lang.uk ? _uk : _en;
}

/// The phone's own choice, for the first run, when nothing was stored yet
Lang phoneLang() =>
    PlatformDispatcher.instance.locales.any((l) => l.languageCode == 'uk')
    ? Lang.uk
    : Lang.en;
