package org.neurofeed.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.androidgamesdk.GameActivity
import java.io.File

/**
 * Hosts the Rust/egui app (libneurofeed.so, `android_main`) via GameActivity.
 * Everything UI lives in Rust; this class only provides what needs Java:
 * runtime permissions, the Storage Access Framework, keep-screen-on and the
 * connectedDevice foreground service.
 */
class MainActivity : GameActivity() {
    companion object {
        private const val TAG = "neurofeed"
        private const val PREFS = "neurofeed"
        private const val KEY_FOLDER = "export_tree"

        @JvmStatic external fun nativeInit(ctx: android.content.Context)
        @JvmStatic external fun nativePicked(name: String, data: ByteArray)
        @JvmStatic external fun nativeFolder(label: String)
        @JvmStatic external fun nativePaused()
        @JvmStatic external fun nativeInsets(left: Int, top: Int, right: Int, bottom: Int)
    }

    private val openDoc = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { readPicked(it) }
    }
    private val openTree = registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri?.let { storeFolder(it) }
    }
    private val askPerms = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { res ->
        Log.i(TAG, "permissions: $res")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState) // loads libneurofeed.so
        nativeInit(this) // btleplug/droidplug needs the app class loader
        folderUri()?.let { nativeFolder(labelOf(it)) }
        requestRuntimePermissions()
        // Status/navigation bars and cutouts: Rust keeps the UI inside them.
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { v, ins ->
            val b = ins.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            nativeInsets(b.left, b.top, b.right, b.bottom)
            ViewCompat.onApplyWindowInsets(v, ins)
        }
    }

    override fun onPause() {
        nativePaused()
        super.onPause()
    }

    private fun requestRuntimePermissions() {
        val want = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            want += Manifest.permission.BLUETOOTH_SCAN
            want += Manifest.permission.BLUETOOTH_CONNECT
        } else {
            want += Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= 33) want += Manifest.permission.POST_NOTIFICATIONS
        val missing = want.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) askPerms.launch(missing.toTypedArray())
    }

    // ---- called from Rust (any thread) ----

    @Suppress("unused")
    fun pickImport() = runOnUiThread { openDoc.launch(arrayOf("*/*")) }

    @Suppress("unused")
    fun pickFolder() = runOnUiThread { openTree.launch(null) }

    @Suppress("unused")
    fun keepScreenOn(on: Boolean) = runOnUiThread {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val svc = Intent(this, CaptureService::class.java)
        try {
            if (on) ContextCompat.startForegroundService(this, svc) else stopService(svc)
        } catch (e: Exception) {
            Log.w(TAG, "foreground service: $e")
        }
    }

    /** Write an export; returns a human-readable location. Throws on failure. */
    @Suppress("unused")
    fun exportFile(name: String, mime: String, data: ByteArray): String {
        val tree = folderUri()
        if (tree != null) {
            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val doc = DocumentsContract.createDocument(contentResolver, parent, mime, name)
                ?: throw IllegalStateException("could not create $name")
            contentResolver.openOutputStream(doc)!!.use { it.write(data) }
            return "${labelOf(tree)}/$name"
        }
        val dir = File(getExternalFilesDir(null) ?: filesDir, "exports").apply { mkdirs() }
        val f = File(dir, name)
        f.writeBytes(data)
        return f.absolutePath
    }

    // ---- SAF helpers ----

    private fun readPicked(uri: Uri) {
        try {
            var name = uri.lastPathSegment ?: "import"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) name = it.getString(0) ?: name
            }
            val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
            nativePicked(name, bytes)
        } catch (e: Exception) {
            Log.e(TAG, "import: $e")
        }
    }

    private fun storeFolder(uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        contentResolver.takePersistableUriPermission(uri, flags)
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(KEY_FOLDER, uri.toString()).apply()
        nativeFolder(labelOf(uri))
    }

    private fun folderUri(): Uri? {
        val s = getSharedPreferences(PREFS, MODE_PRIVATE).getString(KEY_FOLDER, null) ?: return null
        val uri = Uri.parse(s)
        val ok = contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
        return if (ok) uri else null
    }

    private fun labelOf(tree: Uri): String =
        DocumentsContract.getTreeDocumentId(tree).substringAfter(':').ifEmpty { "folder" }
}
