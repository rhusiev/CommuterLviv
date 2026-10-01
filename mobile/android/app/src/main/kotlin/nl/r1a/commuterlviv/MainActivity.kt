package nl.r1a.commuterlviv

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import androidx.core.app.ActivityCompat
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
 * The permission is asked for on the first `start`, never at launch. There is
 * no iOS half yet: the Dart side treats a missing channel as a refusal, so an
 * iPhone gets a dead button rather than a crash.
 */
private const val CHANNEL = "nl.r1a.commuterlviv/here"
private const val FIXES = "nl.r1a.commuterlviv/here/fixes"
private const val REQUEST = 4711

/** Both are AOSP; the coarse one is what a user may downgrade the grant to */
private val PERMISSIONS =
    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

class MainActivity : FlutterActivity(), LocationListener {
    private var fixes: EventChannel.EventSink? = null
    private var asking: MethodChannel.Result? = null
    private var listening = false

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
        waiting.success(granted() && listen())
    }

    override fun onDestroy() {
        unlisten()
        super.onDestroy()
    }

    override fun onPause() {
        // Nothing on this map is worth a fix taken while it is not on screen
        unlisten()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (fixes != null && granted()) listen()
    }
}
