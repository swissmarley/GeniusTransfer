package com.nakya.geniustransfer

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/**
 * The Dart side's door to Android: file pickers that hand over open file
 * descriptors (no copies of multi-GB files), and the sharing service.
 * See lib/platform/host_platform.dart.
 */
class HostChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val launchMediaPicker: () -> Unit,
    private val launchDocumentPicker: () -> Unit,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "geniustransfer/host")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
        SessionService.onStopRequested = {
            main.post { channel.invokeMethod("stopRequested", null) }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        SessionService.onStopRequested = null
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickMedia" -> startPick(result, launchMediaPicker)
            "pickDocuments" -> startPick(result, launchDocumentPicker)
            "clearCopies" -> io.execute {
                copiesDir().deleteRecursively()
                main.post { result.success(null) }
            }
            "startSession" -> {
                SessionService.start(
                    activity,
                    title = call.argument<String>("title") ?: "",
                    text = call.argument<String>("text") ?: "",
                    stopLabel = call.argument<String>("stop") ?: "",
                )
                result.success(null)
            }
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    ContextCompat.checkSelfPermission(
                        activity, Manifest.permission.POST_NOTIFICATIONS
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    ActivityCompat.requestPermissions(
                        activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1
                    )
                }
                result.success(null)
            }
            "stopSession" -> {
                SessionService.stop(activity)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startPick(result: MethodChannel.Result, launch: () -> Unit) {
        if (pendingPick != null) {
            result.error("busy", "A picker is already open.", null)
            return
        }
        pendingPick = result
        try {
            launch()
        } catch (e: Exception) {
            pendingPick = null
            result.error("picker", e.message, null)
        }
    }

    /** Called by MainActivity with the picker's result (empty if cancelled). */
    fun onPicked(uris: List<Uri>) {
        val result = pendingPick ?: return
        pendingPick = null
        io.execute {
            val files = ArrayList<Map<String, Any?>>()
            var lastError: String? = null
            for (uri in uris) {
                try {
                    files.add(open(uri))
                } catch (e: Exception) {
                    lastError = e.message ?: e.toString()
                }
            }
            main.post {
                if (files.isEmpty() && lastError != null) {
                    result.error("open", lastError, null)
                } else {
                    result.success(files)
                }
            }
        }
    }

    /**
     * Opens a picked file. A seekable descriptor (a regular file) is detached
     * and handed to Dart, which reads it with pread, so nothing is copied.
     * Anything else (a pipe, e.g. from a cloud provider) is copied into the
     * app's cache first.
     */
    private fun open(uri: Uri): Map<String, Any?> {
        val resolver = activity.contentResolver
        var name: String? = null
        var modified = 0L
        resolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    .takeIf { it >= 0 && !c.isNull(it) }
                    ?.let { name = c.getString(it) }
                c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    .takeIf { it >= 0 && !c.isNull(it) }
                    ?.let { modified = c.getLong(it) }
                if (modified == 0L) {
                    c.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
                        .takeIf { it >= 0 && !c.isNull(it) }
                        ?.let { modified = c.getLong(it) * 1000 }
                }
            }
        }
        val displayName = safeName(name ?: uri.lastPathSegment ?: "file")

        val pfd = resolver.openFileDescriptor(uri, "r")
            ?: throw IOException("Cannot open $displayName")
        val size = try {
            val end = Os.lseek(pfd.fileDescriptor, 0, OsConstants.SEEK_END)
            Os.lseek(pfd.fileDescriptor, 0, OsConstants.SEEK_SET)
            end
        } catch (e: ErrnoException) {
            -1L // Not seekable: a pipe or a socket.
        }
        if (size >= 0) {
            return mapOf(
                "name" to displayName,
                "size" to size,
                "modified" to modified,
                "fd" to pfd.detachFd(),
            )
        }
        pfd.close()

        val dir = File(copiesDir(), UUID.randomUUID().toString()).apply { mkdirs() }
        val target = File(dir, displayName)
        val input = resolver.openInputStream(uri)
            ?: throw IOException("Cannot read $displayName")
        input.use { source -> target.outputStream().use { source.copyTo(it, 1 shl 20) } }
        return mapOf(
            "name" to displayName,
            "size" to target.length(),
            "modified" to modified,
            "path" to target.absolutePath,
        )
    }

    private fun copiesDir() = File(activity.cacheDir, "shared")

    /** A display name that is also safe as a file name in our cache. */
    private fun safeName(raw: String): String {
        val cleaned = raw.replace(Regex("[/\\\\\\u0000-\\u001f]"), "_").trim().trim('.')
        return cleaned.ifEmpty { "file" }.take(200)
    }
}
