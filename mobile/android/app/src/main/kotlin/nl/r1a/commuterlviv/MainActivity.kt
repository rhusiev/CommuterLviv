package nl.r1a.commuterlviv

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Where the phone is, over `android.location.LocationManager`.
 *
 * This is hand-written rather than `geolocator` because that package pulls
 * `com.google.android.gms:play-services-location`, and F-Droid takes no build
 * with a proprietary SDK in it. LocationManager is AOSP, and all this needs of
 * it is a fix every couple of seconds.
 *
 * The permission is asked for on the first `start`, never at launch. The iOS
 * half is `ios/Runner/Here.swift`, on the same channels.
 *
 * The fixes stop when the app leaves the screen, unless `away` asked for them
 * to go on: then `FollowService` holds them up, on a notification `notice`
 * keeps current.
 */
private const val CHANNEL = "nl.r1a.commuterlviv/here"
private const val FIXES = "nl.r1a.commuterlviv/here/fixes"
private const val REQUEST = 4711
private const val NOTIFY_REQUEST = 4712

/** Both are AOSP; the coarse one is what a user may downgrade the grant to */
private val PERMISSIONS =
    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

class MainActivity : FlutterActivity(), LocationListener {
    private var fixes: EventChannel.EventSink? = null
    private var asking: MethodChannel.Result? = null
    private var listening = false

    /** Following a journey with the app off the screen was asked for */
    private var away = false

    private val locations by lazy { getSystemService(LOCATION_SERVICE) as LocationManager }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val messenger = engine.dartExecutor.binaryMessenger

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" ->
                    if (granted()) {
                        result.success(listen())
                    } else {
                        // One request at a time: a second tap while the system
                        // dialog is up must not leave the first call unanswered
                        asking?.success(false)
                        asking = result
                        ActivityCompat.requestPermissions(this, PERMISSIONS, REQUEST)
                    }
                "stop" -> {
                    unlisten()
                    result.success(null)
                }
                "away" -> {
                    away = call.argument<Boolean>("on") == true
                    if (away) {
                        Notices.channels(
                            this,
                            call.argument<String>("channel") ?: "",
                            call.argument<String>("alerts") ?: "",
                        )
                        askToNotify()
                    } else {
                        stopService(Intent(this, FollowService::class.java))
                        Notices.clear(this)
                    }
                    result.success(!away || follow())
                }
                "notice" -> {
                    if (away) {
                        Notices.say(
                            this,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: "",
                            call.argument<Boolean>("alert") == true,
                        )
                    }
                    result.success(away)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, FIXES).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    fixes = sink
                }

                override fun onCancel(arguments: Any?) {
                    fixes = null
                }
            }
        )
    }

    private fun granted() =
        PERMISSIONS.any {
            ActivityCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

    /**
     * Starts `FollowService`, which needs the location grant first: Android 14
     * refuses a location service to an app without it. False if it cannot run.
     */
    private fun follow(): Boolean {
        if (!granted()) return false
        return try {
            ContextCompat.startForegroundService(this, Intent(this, FollowService::class.java))
            true
        } catch (_: IllegalStateException) {
            // Android 12 refuses a start from the background
            false
        }
    }

    /** Without the grant the service still runs; only its notification is hidden */
    private fun askToNotify() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val notify = Manifest.permission.POST_NOTIFICATIONS
        if (ActivityCompat.checkSelfPermission(this, notify) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        ActivityCompat.requestPermissions(this, arrayOf(notify), NOTIFY_REQUEST)
    }

    /** True if anything is now feeding the stream */
    private fun listen(): Boolean {
        if (listening) return true
        // Both providers, because the one that answers first differs indoors
        // and out, and a fix from either is better than a blank map
        val providers =
            listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).filter {
                locations.allProviders.contains(it)
            }
        if (providers.isEmpty()) return false
        try {
            for (provider in providers) {
                locations.requestLocationUpdates(provider, 2000L, 5f, this)
                locations.getLastKnownLocation(provider)?.let(::onLocationChanged)
            }
        } catch (_: SecurityException) {
            return false
        }
        listening = true
        return true
    }

    private fun unlisten() {
        if (!listening) return
        locations.removeUpdates(this)
        listening = false
    }

    override fun onLocationChanged(fix: Location) {
        fixes?.success(
            mapOf(
                "lat" to fix.latitude,
                "lon" to fix.longitude,
                "accuracy" to fix.accuracy.toDouble(),
                "t" to fix.time.toDouble(),
            )
        )
    }

    override fun onRequestPermissionsResult(
        code: Int,
        permissions: Array<out String>,
        results: IntArray,
    ) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code != REQUEST) return
        val waiting = asking ?: return
        asking = null
        val on = granted() && listen()
        // `away` came while the location dialog was still up
        if (on && away) follow()
        waiting.success(on)
    }

    override fun onDestroy() {
        unlisten()
        stopService(Intent(this, FollowService::class.java))
        super.onDestroy()
    }

    override fun onPause() {
        // Nothing on this map is worth a fix taken while it is not on screen,
        // unless a journey is followed with it off
        if (!away) unlisten()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (fixes != null && granted()) listen()
    }
}
