package com.nakya.geniustransfer

import android.content.Intent
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private var host: HostChannel? = null

    // Registered at construction time, as the Activity Result API requires.
    private val pickMedia =
        registerForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
            host?.onPicked(uris)
        }
    private val pickDocuments =
        registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
            host?.onPicked(uris)
        }
    private val pickFolder =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
            host?.onFolderPicked(tree)
        }
    private val hotspotPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            host?.hotspot?.onPermissionResult(granted)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        host = HostChannel(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            launchMediaPicker = {
                pickMedia.launch(
                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)
                )
            },
            launchDocumentPicker = { pickDocuments.launch(arrayOf("*/*")) },
            launchFolderPicker = { pickFolder.launch(null) },
            requestHotspotPermission = { permission -> hotspotPermission.launch(permission) },
        )
        // Started from another app's share sheet.
        host?.onIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        host?.onIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        host?.dispose()
        host = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
