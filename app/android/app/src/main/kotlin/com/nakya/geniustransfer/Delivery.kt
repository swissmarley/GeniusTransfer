package com.nakya.geniustransfer

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.util.Locale

/** A failed delivery, with the error code the Dart side acts on. */
class DeliveryException(val code: String, message: String) : Exception(message)

/**
 * Puts received files where the user will look for them (PLAN.md §10, question
 * 4): Pictures, Movies or Download › GeniusTransfer by type, or a folder the
 * user picked. Uploads arrive in a private staging folder and only complete
 * files are delivered, so the gallery never shows a half-received one.
 *
 * Nothing is ever overwritten. MediaStore and the documents providers number
 * duplicates themselves ("a (1).jpg"), so we read back the name they chose;
 * on Android 8–9 we number them ourselves.
 */
class Delivery(private val context: Context) {
    private val resolver = context.contentResolver

    companion object {
        private const val APP_FOLDER = "GeniusTransfer"

        /**
         * Free space on the volume holding [path]. The path may not exist
         * yet, so the nearest existing folder above it is measured instead.
         */
        fun freeBytes(path: String): Long? {
            var dir: File? = File(path)
            while (dir != null && !dir.exists()) dir = dir.parentFile
            return dir?.let { runCatching { StatFs(it.path).availableBytes }.getOrNull() }
        }
    }

    /**
     * Copies [source] to its destination, then deletes it. On failure the
     * source stays and nothing is left at the destination.
     *
     * @param folder a tree URI from [keepFolder]; null or blank for the default.
     * @return the final name, a readable location, and the destination's
     *   content URI (a file path on Android 8–9).
     */
    fun deliver(source: File, name: String, mime: String, folder: String?): Map<String, String> {
        // The name is sanitized by the Dart side; this only guards the paths we build.
        if (name.isBlank() || name == "." || name == ".." || name.any { it == '/' || it == '\u0000' }) {
            throw DeliveryException("bad_args", "Not a plain file name: $name")
        }
        if (!source.isFile) throw DeliveryException("failed", "Nothing to deliver at $source")
        val type = mime.substringBefore(';').trim().lowercase(Locale.ROOT)
            .takeIf { it.contains('/') } ?: "application/octet-stream"

        val delivered = when {
            !folder.isNullOrBlank() -> toFolder(source, name, type, folder.toUri())
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> toMediaStore(source, name, type)
            else -> toPublicFolder(source, name, type)
        }
        source.delete()
        return delivered
    }

    /**
     * Keeps write access to a folder the user just picked, across restarts.
     * Returns its id (the tree URI) and the name to show for it.
     */
    fun keepFolder(tree: Uri): Map<String, String> {
        resolver.takePersistableUriPermission(
            tree, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        val name = rootDocument(tree)?.let { folderName(tree, it) } ?: fallbackName(tree)
        return mapOf("id" to tree.toString(), "name" to name)
    }

    /** Android 10+: MediaStore, which needs no permission for the app's own files. */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun toMediaStore(source: File, name: String, mime: String): Map<String, String> {
        var directory = defaultDirectory(mime)
        val item = try {
            insertPending(directory, name, mime)
        } catch (e: Exception) {
            if (directory == Environment.DIRECTORY_DOWNLOADS) throw e
            // Images and Video refuse types they don't know; Downloads takes any.
            directory = Environment.DIRECTORY_DOWNLOADS
            insertPending(directory, name, mime)
        }
        try {
            copy(source, item)
            val published = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            if (resolver.update(item, published, null, null) == 0) {
                throw IOException("Could not publish $name")
            }
        } catch (e: Exception) {
            runCatching { resolver.delete(item, null, null) }
            throw e
        }
        return mapOf(
            "name" to (displayName(item)?.takeIf { it.isNotEmpty() } ?: name),
            "location" to "$directory/$APP_FOLDER",
            "uri" to item.toString(),
        )
    }

    /**
     * Adds an item that stays hidden from other apps until it is published.
     * The collection follows [directory]: Images, Video or Downloads.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun insertPending(directory: String, name: String, mime: String): Uri {
        val volume = MediaStore.VOLUME_EXTERNAL_PRIMARY
        val collection = when (directory) {
            Environment.DIRECTORY_PICTURES -> MediaStore.Images.Media.getContentUri(volume)
            Environment.DIRECTORY_MOVIES -> MediaStore.Video.Media.getContentUri(volume)
            else -> MediaStore.Downloads.getContentUri(volume)
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "$directory/$APP_FOLDER/")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        return resolver.insert(collection, values) ?: throw IOException("MediaStore refused $name")
    }

    /**
     * Android 8–9: a plain file copy, plus a media scan so Gallery sees it.
     * Without the storage permission, the app's own folder on shared storage,
     * which needs none.
     */
    private fun toPublicFolder(source: File, name: String, mime: String): Map<String, String> {
        val directory = defaultDirectory(mime)
        val shared = ContextCompat.checkSelfPermission(
            context, Manifest.permission.WRITE_EXTERNAL_STORAGE
        ) == PackageManager.PERMISSION_GRANTED
        val dir: File
        val location: String
        if (shared) {
            dir = File(Environment.getExternalStoragePublicDirectory(directory), APP_FOLDER)
            location = "$directory/$APP_FOLDER"
        } else {
            dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                ?: throw IOException("Shared storage is not available")
            location = "Android/data/${context.packageName}/files/${Environment.DIRECTORY_DOWNLOADS}"
        }
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("Cannot create $dir")

        val target = reserveName(dir, name)
        try {
            copy(source, FileOutputStream(target))
        } catch (e: Exception) {
            target.delete()
            throw e
        }
        if (shared) {
            MediaScannerConnection.scanFile(context, arrayOf(target.path), arrayOf(mime), null)
        }
        return mapOf("name" to target.name, "location" to location, "uri" to target.absolutePath)
    }

    /** Creates "a.jpg", or "a (1).jpg", "a (2).jpg"… if taken, atomically. */
    private fun reserveName(dir: File, name: String): File {
        val dot = name.lastIndexOf('.').takeIf { it > 0 } ?: name.length
        val base = name.substring(0, dot)
        val extension = name.substring(dot)
        for (n in 0..9999) {
            val file = File(dir, if (n == 0) name else "$base ($n)$extension")
            if (file.createNewFile()) return file
        }
        throw IOException("No free name for $name in $dir")
    }

    /**
     * A folder the user picked, through its documents provider. If access was
     * revoked or the folder is gone (deleted, SD card removed), fails with
     * "folder_unavailable" and the Dart side falls back to the default.
     */
    private fun toFolder(source: File, name: String, mime: String, tree: Uri): Map<String, String> {
        val root = rootDocument(tree)
        val location = if (root != null && canWrite(tree)) folderName(tree, root) else null
        if (root == null || location == null) {
            throw DeliveryException("folder_unavailable", "The chosen folder is no longer available.")
        }
        val document = try {
            DocumentsContract.createDocument(resolver, root, mime, name)
        } catch (e: Exception) {
            throw DeliveryException("folder_unavailable", e.message ?: e.toString())
        } ?: throw DeliveryException("folder_unavailable", "Cannot create $name in $location.")
        try {
            copy(source, document)
        } catch (e: Exception) {
            runCatching { DocumentsContract.deleteDocument(resolver, document) }
            throw e
        }
        return mapOf(
            "name" to (displayName(document)?.takeIf { it.isNotEmpty() } ?: name),
            "location" to location,
            "uri" to document.toString(),
        )
    }

    private fun canWrite(tree: Uri) =
        resolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }

    /** The document at the top of a picked tree; null if [tree] isn't a tree URI. */
    private fun rootDocument(tree: Uri): Uri? =
        if (DocumentsContract.isTreeUri(tree)) {
            DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        } else {
            null
        }

    /** The picked folder's name; null if its provider can't find it any more. */
    private fun folderName(tree: Uri, root: Uri): String? =
        displayName(root)?.ifEmpty { fallbackName(tree) }

    /** "primary:DCIM/Camera" → "Camera", for a folder its provider doesn't name. */
    private fun fallbackName(tree: Uri): String {
        val segment = tree.lastPathSegment.orEmpty()
        return segment.substringAfterLast('/').substringAfterLast(':').ifEmpty { segment }
    }

    /**
     * The display name of a MediaStore item or a document: null if it can't
     * be found or read, empty if its provider gives it no name.
     */
    private fun displayName(uri: Uri): String? = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (!c.moveToFirst()) return@use null
            c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                .takeIf { it >= 0 && !c.isNull(it) }
                ?.let { c.getString(it) }
                .orEmpty()
        }
    } catch (e: Exception) {
        null
    }

    /** Pictures, Movies or Download, by type. */
    private fun defaultDirectory(mime: String): String = when {
        mime.startsWith("image/") -> Environment.DIRECTORY_PICTURES
        mime.startsWith("video/") -> Environment.DIRECTORY_MOVIES
        else -> Environment.DIRECTORY_DOWNLOADS
    }

    private fun copy(source: File, destination: Uri) {
        val output = resolver.openOutputStream(destination, "w")
            ?: throw IOException("Cannot write to $destination")
        copy(source, output)
    }

    /**
     * Copies, syncs and closes. The sync makes sure the copy is on disk
     * before the caller deletes the source.
     */
    private fun copy(source: File, output: OutputStream) {
        output.use { out ->
            source.inputStream().use { it.copyTo(out, 1 shl 20) }
            (out as? FileOutputStream)?.let { runCatching { it.fd.sync() } }
        }
    }
}
