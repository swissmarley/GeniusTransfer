package com.nakya.geniustransfer

import android.content.Intent
import android.os.Bundle
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private var host: HostChannel? = null

    /** Recreated after the process died: the Intent is an old one. */
    private var restored = false

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
    private val hotspotPermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { answers ->
            host?.hotspot?.onPermissionResult(answers)
        }
    private val permission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            host?.onPermissionResult()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        restored = savedInstanceState != null
        super.onCreate(savedInstanceState)
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
            requestPermission = { name -> permission.launch(name) },
            requestHotspotPermissions = { names -> hotspotPermissions.launch(names) },
        )
        // Started from another app's share sheet. Not when Android brings
        // back an old Intent (from Recents, or after the process died).
        val fromHistory =
            intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (!restored && !fromHistory) host?.onIntent(intent)
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
