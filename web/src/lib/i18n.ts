/** Ukrainian and English, chosen once per load.
 *
 * The app is for Lviv, so Ukrainian is the default and English is the fallback
 * for anyone whose browser asks for it. There is no interpolation and no
 * plural machinery: every string that carries a number takes it as an
 * argument, which is enough for the twelve of them and stops the dictionary
 * from becoming a small language.
 *
 * `t` is read at module level rather than through a context, so changing the
 * language reloads the page - it happens once, if ever, and a reload is
 * cheaper than threading a provider through every component. */

export type Lang = "uk" | "en";

const key = "commuterlviv.lang";

const en = {
  appName: "CommuterLviv",
  signIn: "Sign in",
  signInHint: "Sign in to see the map",
  inviteHint: "Pick a name and a password to take up this invite",
  registerHint: "Pick a name and a password",
  username: "Username",
  password: "Password",
  passwordHint: "At least 10 characters",
  stayIn: "Stay signed in on this device",
  createAccount: "Create the account",
  haveAccount: "I already have an account",
  wantAccount: "Create an account",
  wrong: "something went wrong",
  routes: "Routes",
  map: "Map",
  times: "Times",
  sets: "Sets",
  saveSet: "Save the current selection into this set",
  deleteSet: "Delete this set",
  newSet: "New set from selection",
  add: "add",
  save: "save",
  clear: "clear",
  filter: "Filter",
  on: (n: number) => `${n} on`,
  basemap: "Map",
  language: "Language",
  failed: "that did not work",
  findStop: "Find a stop",
  nearMe: "Stops near me",
  noGeolocation: "this browser will not say where it is",
  nothingNear: "no stop within 2 km of where you are",
  away: (m: number) => `${m} m`,
  whereAmI: "Where I am",
  noLocation: "Location is not available",
  stopsAhead: "Stops ahead",
  vehicleGone: "This one is no longer being tracked",
  vehicles: (n: number) => `${n} vehicles`,
  out: "out",
  loading: "loading the city",
  waiting: "…",
  tryAgain: "try again",
  noService: "the service is not answering",
  pin: "pin",
  pinned: "pinned",
  unpin: "unpin",
  routeCount: (n: number) => `${n} routes`,
  nothingPinned: "Nothing pinned yet. Tap a stop on the map and pin it to watch it here.",
  nothingDue: "nothing due on the routes shown",
  now: "now",
  oneMinute: "1 min",
  minutes: (n: number) => `${n} min`,
};

type Strings = typeof en;

const uk: Strings = {
  appName: "CommuterLviv",
  signIn: "Увійти",
  signInHint: "Увійдіть, щоб побачити мапу",
  inviteHint: "Оберіть імʼя та пароль, щоб скористатися запрошенням",
  registerHint: "Оберіть імʼя та пароль",
  username: "Імʼя",
  password: "Пароль",
  passwordHint: "Щонайменше 10 символів",
  stayIn: "Не виходити на цьому пристрої",
  createAccount: "Створити акаунт",
  haveAccount: "У мене вже є акаунт",
  wantAccount: "Створити акаунт",
  wrong: "щось пішло не так",
  routes: "Маршрути",
  map: "Мапа",
  times: "Час",
  sets: "Набори",
  saveSet: "Зберегти поточний вибір у цей набір",
  deleteSet: "Видалити цей набір",
  newSet: "Новий набір із вибраного",
  add: "додати",
  save: "зберегти",
  clear: "очистити",
  filter: "Пошук",
  on: (n: number) => `увімкнено ${n}`,
  basemap: "Вигляд мапи",
  language: "Мова",
  failed: "не вдалося",
  findStop: "Знайти зупинку",
  nearMe: "Зупинки поруч",
  noGeolocation: "цей браузер не каже, де він",
  nothingNear: "немає зупинки ближче ніж за 2 км",
  away: (m: number) => `${m} м`,
  whereAmI: "Де я",
  noLocation: "Місцеперебування недоступне",
  stopsAhead: "Наступні зупинки",
  vehicleGone: "Цей транспорт більше не відстежується",
  vehicles: (n: number) => `${n} у русі`,
  out: "вийти",
  loading: "завантажуємо місто",
  waiting: "…",
  tryAgain: "спробувати ще",
  noService: "сервіс не відповідає",
  pin: "закріпити",
  pinned: "закріплено",
  unpin: "відкріпити",
  routeCount: (n: number) => `маршрутів: ${n}`,
  nothingPinned:
    "Поки нічого не закріплено. Торкніться зупинки на мапі та закріпіть її, щоб стежити тут.",
  nothingDue: "на показаних маршрутах нічого не їде",
  now: "зараз",
  oneMinute: "1 хв",
  minutes: (n: number) => `${n} хв`,
};

/** What was chosen before, else Ukrainian for a browser that asks for it. */
function pick(): Lang {
  const held = localStorage.getItem(key);
  if (held === "uk" || held === "en") return held;
  return navigator.languages.some((l) => l.startsWith("uk")) ? "uk" : "en";
}

export const lang = pick();
export const t: Strings = lang === "uk" ? uk : en;

export function setLang(next: Lang) {
  localStorage.setItem(key, next);
  location.reload();
}
