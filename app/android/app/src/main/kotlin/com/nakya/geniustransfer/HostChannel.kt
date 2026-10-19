package com.nakya.geniustransfer

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
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
 * descriptors (no copies of multi-GB files), the sharing service, and putting
 * received files where the user finds them (see [Delivery]).
 * See lib/platform/host_platform.dart.
 */
class HostChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val launchMediaPicker: () -> Unit,
    private val launchDocumentPicker: () -> Unit,
    private val launchFolderPicker: () -> Unit,
    private val requestPermission: (String) -> Unit,
    requestHotspotPermissions: (Array<String>) -> Unit,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "geniustransfer/host")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val delivery = Delivery(activity.applicationContext)
    val hotspot = Hotspot(activity, requestHotspotPermissions) {
        main.post { channel.invokeMethod("hotspotStopped", null) }
    }

    /** The caller waiting for a permission dialog's answer. */
    private var pendingPermission: MethodChannel.Result? = null

    private val stopListener: () -> Unit = {
        main.post { channel.invokeMethod("stopRequested", null) }
    }

    /** The caller of the open picker. One picker at a time, of any kind. */
    private var pendingPick: MethodChannel.Result? = null

    /** Files another app shared with us, until the Dart side takes them. */
    private var shared: List<Uri> = emptyList()

    init {
        channel.setMethodCallHandler(this)
        SessionService.onStopRequested = stopListener
    }

    fun dispose() {
        hotspot.stop()
        channel.setMethodCallHandler(null)
        if (SessionService.onStopRequested === stopListener) {
            SessionService.onStopRequested = null
        }
        pendingPermission?.success(null)
        pendingPermission = null
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickMedia" -> startPick(result, launchMediaPicker)
            "pickDocuments" -> startPick(result, launchDocumentPicker)
            "pickFolder" -> startPick(result, launchFolderPicker)
            "takeSharedFiles" -> {
                val uris = shared
                shared = emptyList()
                openAll(uris, result)
            }
            "deliverFile" -> deliverFile(call, result)
            "freeBytes" -> {
                val path = call.argument<Any>("path") as? String
                if (path == null) {
                    result.error("bad_args", "freeBytes needs a path.", null)
                } else {
                    // A single statfs: answered here, so it never waits
                    // behind a long delivery on io.
                    result.success(Delivery.freeBytes(path))
                }
            }
            "requestStoragePermission" -> {
                // Android 8–9 only, to save into Pictures, Movies and Download.
                // Without it, received files go to the app's own folder.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    askFor(Manifest.permission.WRITE_EXTERNAL_STORAGE, result)
                } else {
                    result.success(null)
                }
            }
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
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    askFor(Manifest.permission.POST_NOTIFICATIONS, result)
                } else {
                    result.success(null)
                }
            }
            "stopSession" -> {
                SessionService.stop(activity)
                result.success(null)
            }
            "openFile" -> openFile(call, result)
            "startHotspot" -> hotspot.start(result)
            "stopHotspot" -> {
                hotspot.stop()
                result.success(null)
            }
            "openLocationSettings" -> {
                hotspot.openLocationSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Shows the permission dialog if needed and replies once the user has
     * answered. Android cancels a second dialog requested while one is
     * showing, so the Dart side waits for each before asking for the next.
     */
    private fun askFor(permission: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED || pendingPermission != null
        ) {
            result.success(null)
            return
        }
        pendingPermission = result
        requestPermission(permission)
    }

    /** MainActivity forwards the answer to [askFor]'s dialog here. */
    fun onPermissionResult() {
        pendingPermission?.success(null)
        pendingPermission = null
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
        openAll(uris, result)
    }

    /**
     * Called by MainActivity with the Intent it was started or brought back
     * with. "Share › GeniusTransfer" from another app (ACTION_SEND or
     * ACTION_SEND_MULTIPLE) hands us its files; the Dart side is told and
     * takes them with takeSharedFiles, then opens the Send screen.
     */
    fun onIntent(intent: Intent?) {
        if (intent == null || intent.getBooleanExtra(HANDLED, false)) return
        val uris = sharedUris(intent)
        if (uris.isEmpty()) return
        // The same Intent comes back after a rotation; take its files once.
        intent.putExtra(HANDLED, true)
        shared = uris
        main.post { channel.invokeMethod("sharedFilesAvailable", null) }
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND ->
            listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        Intent.ACTION_SEND_MULTIPLE ->
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.filterNotNull()
                ?: emptyList()
        else -> emptyList()
    }

    /**
     * Opens a received file (a content URI) in the app the user prefers for
     * its type. Replies false if no installed app can open it.
     */
    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<Any>("uri") as? String
        if (uri == null || !uri.startsWith("content:")) {
            result.error("bad_args", "openFile needs a content URI.", null)
            return
        }
        val mime = (call.argument<Any>("mime") as? String) ?: "*/*"
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse(uri), mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            activity.startActivity(view)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.success(false)
        }
    }

    /** Opens [uris] on io and replies with what the Dart side needs for each. */
    private fun openAll(uris: List<Uri>, result: MethodChannel.Result) {
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

    /** Called by MainActivity with the folder picker's result (null if cancelled). */
    fun onFolderPicked(tree: Uri?) {
        val result = pendingPick ?: return
        pendingPick = null
        if (tree == null) {
            result.success(null)
            return
        }
        io.execute {
            try {
                val folder = delivery.keepFolder(tree)
                main.post { result.success(folder) }
            } catch (e: Exception) {
                main.post { result.error("picker", e.message ?: e.toString(), null) }
            }
        }
    }

    /**
     * Moves a received file from staging to its destination. The copy can
     * take a while for a big video, so it runs on io.
     */
    private fun deliverFile(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<Any>("source") as? String
        val name = call.argument<Any>("name") as? String
        val mime = call.argument<Any>("mime") as? String
        val folderArg = call.argument<Any>("folder")
        val folder = folderArg as? String
        if (source.isNullOrEmpty() || name == null || mime == null ||
            (folderArg != null && folder == null)
        ) {
            result.error("bad_args", "deliverFile needs source, name, mime and an optional folder.", null)
            return
        }
        io.execute {
            try {
                val delivered = delivery.deliver(File(source), name, mime, folder)
                main.post { result.success(delivered) }
            } catch (e: DeliveryException) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message ?: e.toString(), null) }
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

    private companion object {
        const val HANDLED = "com.nakya.geniustransfer.HANDLED"
    }
}
