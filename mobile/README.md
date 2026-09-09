# The phone app

A second client for `commuterlviv serve`. It adds no endpoint and no model: the
browser and the phone see the same city, the same route sets and the same
predictions. What it does not share is the browser, so a little of the browser
is written out by hand here.

## Running it

The toolchain lives under XDG paths; `/tmp/flutterenv.sh` exports the lot.

```sh
source /tmp/flutterenv.sh
cd mobile
flutter pub get
flutter test                       # the wire decoder against bytes Python made
flutter analyze
flutter run --dart-define=COMMUTERLVIV_BASE=http://10.0.2.2:8099
```

Without that `--dart-define` the app talks to `https://commuterlviv.r1a.nl`, which is
where it is published; an F-Droid build passes nothing, so the default has to be
the real server. `10.0.2.2` is the host machine as the Android emulator sees it.
On a real phone use the machine's address on the network - and note that plain
`http` works only in a debug build:
`android/app/src/debug/AndroidManifest.xml` allows cleartext and the release
manifest does not. Either way the address is editable in the app - from the
sign-in screen, and from the menu once signed in - and remembered. Changing it
drops the session, the cookies and the cached catalogue, because all three
belonged to the old server, and the app returns to the sign-in screen.

There is no emulator in the SDK by default. One, on the same XDG paths:

```sh
sdkmanager --install emulator "system-images;android-35;default;x86_64"
avdmanager create avd -n commuterlviv -k "system-images;android-35;default;x86_64" -d pixel_6
emulator -avd commuterlviv -no-snapshot -no-audio -no-boot-anim -gpu swangle_indirect
```

`swangle_indirect` and not the default `swiftshader_indirect`: on Fedora 44 the
bundled SwiftShader's JIT segfaults the emulator seconds after boot, every time,
with the crash inside `emulator/lib64/gles_swiftshader/libGLESv2.so`. SwANGLE
boots, but then the host's `gfxstream` GLES2 decoder takes a SIGILL the moment
Flutter draws its first frame, so start the app asking for software rendering:

```sh
adb shell am start -n ua.lviv.commuterlviv/.MainActivity \
  --ez enable-software-rendering true --ez enable-impeller false
```

`flutter run` cannot pass those, so on an emulator install the APK and start it
this way. A real phone needs none of this.

A release build:

```sh
flutter build apk --release
```

It comes out unsigned unless `android/key.properties` exists, which is what
F-Droid needs. See `fdroid/ua.lviv.commuterlviv.yml` for the rest.

## What the server needs

One line of deployment configuration, because the app is not a web page and has
no web origin:

```
COMMUTERLVIV_ORIGINS=https://commuterlviv.r1a.nl,app://commuterlviv
```

`app://commuterlviv` is a scheme no browser will ever mint, so listing it cannot
widen what a web page is allowed to do. Without it the websocket handshake is
refused and the map stays empty while everything else works.

## How it is put together

| file | what it is |
| --- | --- |
| `lib/src/wire.dart` | the 10-byte frame decoder, a port of `commuterlviv/live/wire.py` |
| `lib/src/api.dart` | cookies, the CSRF token and the `Origin` header - the browser part |
| `lib/src/live.dart` | the socket, the vehicles, and where each one is right now |
| `lib/src/vehicle_layer.dart` | one `CustomPaint` for the whole city |
| `lib/src/home.dart` | the state both tabs share, and nothing that draws |
| `lib/src/map_tab.dart` | the basemap, the vehicles and the attribution |
| `lib/src/times_tab.dart` | the pinned stops and what is due at each |
| `lib/src/stop_card.dart` | one stop, from the bottom of the map |
| `lib/src/stop_search.dart` | stops by name, scanned on every keystroke |
| `lib/src/sheets.dart` | the route sheet and the basemap sheet |
| `lib/src/due.dart` | one route's countdown chip, drawn in three places |
| `lib/src/server_dialog.dart` | which server to talk to, asked from two places |
| `lib/src/map_theme.dart` | the five basemap styles and the colours drawn over them |
| `lib/src/map_controls.dart` | zoom, and the compass that shows up off north |
| `lib/src/eta.dart` | an arrival's absolute time, said as a countdown |
| `lib/src/map_tiles.dart` | where the basemap is kept between runs |

Seven things are worth knowing before changing any of it.

**A password manager cannot see a Flutter form.** The whole app is one native
view, so Bitwarden and the rest are offered nothing to fill unless the fields
announce themselves: the sign-in form is an `AutofillGroup` and its two fields
carry `AutofillHints.username` and `AutofillHints.password`, or `newPassword`
while joining. `_submit` then calls `TextInput.finishAutofillContext()` - the
form is never dismissed the way a native one is, so without that call the
manager is never asked whether to save.

**Nothing on the map is a widget.** Four hundred vehicles are four hundred
circles in one painter, repainted from a `Ticker` at the display's rate. The
socket delivers a position every five seconds and `sample()` eases between the
last two, so movement is smooth without the network being fast. Widgets listen
to `Live` only for what changes rarely: the connection, the arrival times, and
whether any vehicle went away.

**Route badges are laid out once.** A `ui.Paragraph` per route, cached in a map.
Laying out text is far dearer than drawing text already laid out, and doing it
per vehicle per frame is the one thing that would not fit in a frame.

**The basemap style carries an id that the app puts there.** `vector_map_tiles`
renders each tile to a PNG and caches it on disk under `'${theme.id}-v${theme
.version}'`, and every VersaTiles style parses to a theme whose id is `default`.
So `_loadStyle` rebuilds the `Style` with `theme: read.theme.copyWith(id:
theme.id)`. Without that, picking a second style changes the overlay colours and
nothing else: the map keeps showing the first style's pictures, read back from
disk, across restarts.

**An arrow is a claim.** The wire's flag bit 1 says the tracker is confident the
vehicle is moving, and the wedge is drawn only then. This is the same
conservatism the web UI applies, decided once on the server so both clients say
the same thing.

**A pinch always carries a twist, and the map must ignore it.** `flutter_map`'s
`rotationThreshold` does nothing on its own: with
`enableMultiFingerGestureRace` off, which is the package's default, every
multi-finger gesture runs at once and every threshold is skipped, so two
fingers spreading a degree or two apart turn the map from the first degree.
`mapInteraction` in `lib/src/map_controls.dart` turns the race on, which makes
one gesture win the whole touch: 12° of twist or 0.35 zoom levels of spread,
zoom tested first. Rotation's win set is widened to `MultiFingerGesture.all`,
because the default lets a won rotation lock zooming out until the fingers
lift. `test/map_gestures_test.dart` drives two pointers through both cases.

**The basemap outlives the cache directory.** `vector_map_tiles` keeps its
rendered tiles under the temporary directory by default, which on Android is
the cache the system empties whenever it wants space - so the city a rider
downloaded yesterday is gone exactly when there is no signal to fetch it again.
`lib/src/map_tiles.dart` points `cacheFolder` at a `tiles` folder under
application support instead, 200 MB kept for 90 days, with 32 MB of tile bytes
and 50 parsed tiles in memory. `flutter analyze` calls that assignment an error
and is wrong: it resolves the package's conditional export to the web stub,
where `Directory` is a `String`, while the compiler picks the `dart:io` one.
Hence the `ignore` comment at the call in `home.dart`.

## Where the phone is

The locate button is a hand-written platform channel, not a package. The obvious
package, `geolocator`, pulls `com.google.android.gms:play-services-location`,
and F-Droid does not take builds with a proprietary SDK in them; so each
platform has its own half, answering the same two channels -
`ua.lviv.commuterlviv/here` for `start` and `stop`,
`ua.lviv.commuterlviv/here/fixes` for a `{lat, lon, accuracy}` map per fix - so
that `here.dart` has one code path.

`MainActivity.kt` is the Android half, over `android.location.LocationManager`,
which is AOSP. It asks both providers, GPS and network, because which one
answers first differs indoors and out. `ios/Runner/Here.swift` is the iOS half,
over `CoreLocation`, which is part of the system; `AppDelegate.swift` owns it
and hands it the app's trips in and out of the background. Both stop the
updates while the app is off screen: no fix is taken while the map is not on
it.

`ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` are declared, and asked for
on the first press of the button - never at launch. The fix stays on the phone:
`lib/src/here.dart` holds it, the layer draws it, and nothing sends it to the
service, which has no use for it.

**The iOS half is unbuilt.** It is written but has never been through a
compiler: there is no Mac here, and `flutter build ios` needs one. Read it as a
first draft until somebody with Xcode runs it. Everything else here - the
missing channel reading as a refusal - still holds on any third platform.

## Not in this version

**`vector_map_tiles` is on `9.0.0-beta.13`.** Not by choice: it is the version
compatible with `flutter_map 8.3.2`. Worth revisiting when either goes stable.
