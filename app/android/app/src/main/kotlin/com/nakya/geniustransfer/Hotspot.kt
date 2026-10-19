package com.nakya.geniustransfer

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import io.flutter.plugin.common.MethodChannel

/**
 * A local-only hotspot: a Wi-Fi network this phone creates just for the
 * guest, without sharing its internet connection, for when the two devices
 * share no network. Android picks the name and password; the Dart side shows
 * them as a "join this Wi-Fi" QR code.
 *
 * Android 13+ needs the Nearby Wi-Fi devices permission; before that, fine
 * location, with Location turned on. It must be started while the app is in
 * the foreground, and stays on until [stop] or until the system stops it.
 */
class Hotspot(
    private val activity: Activity,
    private val requestPermissions: (Array<String>) -> Unit,
    private val onStopped: () -> Unit,
) {
    private val wifi =
        activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val main = Handler(Looper.getMainLooper())
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null

    /** The caller waiting for a permission answer or for the hotspot. */
    private var pending: MethodChannel.Result? = null

    /** [stop] came while Android was still starting the hotspot. */
    private var cancelled = false

    /** Replies with `{ssid, password}`, or an error code for the Dart side. */
    fun start(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "The hotspot is already starting.", null)
            return
        }
        reservation?.let { current ->
            describe(current)?.let { return result.success(it) }
        }
        pending = result
        cancelled = false
        if (ContextCompat.checkSelfPermission(activity, requiredPermission()) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            begin()
        } else {
            requestPermissions(permissionsToRequest())
        }
    }

    /**
     * MainActivity forwards the permission dialog's answers here. An empty
     * map means the request was cancelled (for example because another
     * permission dialog was showing).
     */
    fun onPermissionResult(answers: Map<String, Boolean>) {
        if (pending == null) return
        if (answers[requiredPermission()] == true) {
            begin()
        } else {
            fail("permission", "Permission to create a hotspot was refused.")
        }
    }

    fun stop() {
        // A start still in progress must not leave a hotspot behind.
        if (pending != null) cancelled = true
        reservation?.close()
        reservation = null
    }

    fun openLocationSettings() {
        activity.startActivity(
            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun begin() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU && !locationEnabled()) {
            // Android 8–12 refuse to start a hotspot with Location off.
            fail("location_off", "Location is off.")
            return
        }
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(started: WifiManager.LocalOnlyHotspotReservation) {
                    if (cancelled) {
                        started.close()
                        fail("failed", "The session ended while the hotspot was starting.")
                        return
                    }
                    val info = describe(started)
                    if (info == null) {
                        started.close()
                        fail("failed", "The hotspot has no name or password.")
                        return
                    }
                    reservation = started
                    succeed(info)
                }

                override fun onStopped() {
                    reservation = null
                    onStopped.invoke()
                }

                override fun onFailed(reason: Int) {
                    if (pending == null && reservation != null) {
                        // It was running and broke down: same as stopped.
                        reservation?.close()
                        reservation = null
                        onStopped.invoke()
                        return
                    }
                    val code = if (reason == ERROR_INCOMPATIBLE_MODE) "tethering_on" else "failed"
                    fail(code, "The hotspot could not start (reason $reason).")
                }
            }, main)
        } catch (e: SecurityException) {
            fail("permission", e.message)
        } catch (e: IllegalStateException) {
            // For example "Caller already has an active LocalOnlyHotspot request".
            fail("failed", e.message)
        }
    }

    private fun succeed(info: Map<String, String?>) {
        val result = pending ?: return
        pending = null
        result.success(info)
    }

    private fun fail(code: String, message: String?) {
        val result = pending ?: return
        pending = null
        result.error(code, message, null)
    }

    private fun requiredPermission() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.NEARBY_WIFI_DEVICES
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }

    /**
     * Android 12 ignores a request for fine location that does not also ask
     * for coarse location, so ask for both there (and before).
     */
    private fun permissionsToRequest(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            )
        }

    private fun locationEnabled(): Boolean {
        val location = activity.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return false
        return LocationManagerCompat.isLocationEnabled(location)
    }

    /** The network's name and password, or null if Android does not say. */
    private fun describe(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String?>? {
        val (ssid, password) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = r.softApConfiguration
            ssidOf(config) to config.passphrase
        } else {
            legacyCredentials(r)
        }
        if (ssid.isNullOrEmpty()) return null
        return mapOf("ssid" to ssid, "password" to password)
    }

    @Suppress("DEPRECATION")
    private fun ssidOf(config: android.net.wifi.SoftApConfiguration): String? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // A UTF-8 name comes back in double quotes, anything else as hex.
            config.wifiSsid?.toString()?.removeSurrounding("\"")
        } else {
            config.ssid
        }

    @Suppress("DEPRECATION")
    private fun legacyCredentials(
        r: WifiManager.LocalOnlyHotspotReservation,
    ): Pair<String?, String?> {
        val config = r.wifiConfiguration ?: return null to null
        return config.SSID?.removeSurrounding("\"") to config.preSharedKey?.removeSurrounding("\"")
    }
}
