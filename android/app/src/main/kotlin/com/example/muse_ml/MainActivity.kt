package com.example.muse_ml

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import android.util.Log

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "muse_ml/saf"
        private const val REQ_PICK_DIR = 7401
        private const val TAG = "muse_saf"

        // Defined in Rust (rust/src/api/muse.rs) — initializes btleplug's
        // global Android adapter before any BLE operation.
        @JvmStatic external fun museAndroidInit()

        init {
            System.loadLibrary("rust_lib_muse_ml")
        }
    }

    private var pendingResult: Result? = null
    private var lastTreeUri: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        museAndroidInit()
        super.onCreate(savedInstanceState)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK_DIR) {
            val pending = pendingResult ?: return
            pendingResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }
            val uri = data.data!!
            val takeFlags = (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            try {
                contentResolver.takePersistableUriPermission(uri, takeFlags)
            } catch (e: Exception) {
                Log.w(TAG, "could not persist URI permission: $e")
            }
            val tree = uri.toString()
            lastTreeUri = tree
            pending.success(tree)
        }
    }

    private fun handle(call: MethodCall, result: Result) {
        when (call.method) {
            "getDir" -> {
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                }
                startActivityForResult(intent, REQ_PICK_DIR)
            }
            "ensureDir" -> { result.success(null); }
            "writeFile" -> writeFile(call, result)
            "writeFileAtomic" -> writeFileAtomic(call, result)
            "readFile" -> readFile(call, result)
            "readFilePrefix" -> readFilePrefix(call, result)
            "deleteFile" -> deleteFile(call, result)
            "listFiles" -> listFiles(call, result)
            else -> result.notImplemented()
        }
    }

    private fun treeUri(call: MethodCall): Uri? {
        val tree = call.argument<String>("tree") ?: return null
        return Uri.parse(tree)
    }

    /// Resolve a child document by its display [name] inside [tree]. Returns
    /// the document URI, or null if no child with that name exists.
    ///
    /// `buildDocumentUriUsingTree(tree, name)` cannot be used directly: it
    /// expects the child's *document ID* (e.g. `primary:Med fed/session_x`),
    /// not the bare display name, so it must be looked up via the tree query.
    private fun resolveDoc(tree: Uri, name: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree)
        )
        contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null, null, null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val display = cursor.getString(1) ?: continue
                if (display == name) {
                    val id = cursor.getString(0) ?: return null
                    return DocumentsContract.buildDocumentUriUsingTree(tree, id)
                }
            }
        }
        return null
    }

    private fun writeFile(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        val name = call.argument<String>("name")
        val bytes = call.argument<ByteArray>("bytes")
        if (tree == null || name == null || bytes == null) {
            result.error("bad_args", "tree/name/bytes required", null)
            return
        }
        try {
            var doc = resolveDoc(tree, name)
            if (doc == null) {
                // Document doesn't exist yet — create it first, then write.
                val parent = DocumentsContract.buildDocumentUriUsingTree(
                    tree, DocumentsContract.getTreeDocumentId(tree)
                )
                val created = DocumentsContract.createDocument(
                    contentResolver, parent, "application/octet-stream", name
                )
                if (created == null) {
                    result.error("open_failed", "could not create $name", null)
                    return
                }
                doc = created
            }
            val out = contentResolver.openOutputStream(doc, "wt")
                ?: run {
                    result.error("open_failed", "could not open $name for writing", null)
                    return
                }
            out.use { it.write(bytes) }
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "writeFile $name failed", e)
            result.error("write_failed", e.toString(), null)
        }
    }

    /// Same as [writeFile] but crash-safe: SAF has no atomic rename, so we do
    /// the closest safe sequence — write the bytes to a sibling `name.mtmp`
    /// document, sync it, delete the old target, then rename the temp over it.
    ///
    /// A crash in the window between the delete and the rename leaves the
    /// target missing with `name.mtmp` intact; [recoverDoc] rolls that forward
    /// on the next read. A crash before the delete leaves the old target intact
    /// plus a stale `.mtmp`, which [recoverDoc] discards.
    private fun writeFileAtomic(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        val name = call.argument<String>("name")
        val bytes = call.argument<ByteArray>("bytes")
        if (tree == null || name == null || bytes == null) {
            result.error("bad_args", "tree/name/bytes required", null)
            return
        }
        try {
            val tmpName = "$name.mtmp"
            // 1. Write the full new content to a sibling temp document.
            var tmpDoc = resolveDoc(tree, tmpName)
            if (tmpDoc == null) {
                val parent = DocumentsContract.buildDocumentUriUsingTree(
                    tree, DocumentsContract.getTreeDocumentId(tree)
                )
                tmpDoc = DocumentsContract.createDocument(
                    contentResolver, parent, "application/octet-stream", tmpName
                )
                if (tmpDoc == null) {
                    result.error("open_failed", "could not create $tmpName", null)
                    return
                }
            }
            contentResolver.openOutputStream(tmpDoc, "wt")?.use { it.write(bytes) }
                ?: run {
                    result.error("open_failed", "could not open $tmpName for writing", null)
                    return
                }
            // 2. Remove the old target (leaving the temp intact), then swap.
            val oldDoc = resolveDoc(tree, name)
            if (oldDoc != null) {
                DocumentsContract.deleteDocument(contentResolver, oldDoc)
            }
            val renamed = DocumentsContract.renameDocument(contentResolver, tmpDoc, name)
            if (renamed == null) {
                result.error("rename_failed", "could not rename $tmpName -> $name", null)
                return
            }
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "writeFileAtomic $name failed", e)
            result.error("write_failed", e.toString(), null)
        }
    }

    /// Heal a `name.mtmp` sibling left behind by an interrupted
    /// [writeFileAtomic]: if the target is missing but the temp exists, rename
    /// the temp into place; if both exist, the temp is a stale leftover and is
    /// discarded. Called before every read so a mid-swap crash cannot leave the
    /// history unreadable.
    private fun recoverDoc(tree: Uri, name: String) {
        try {
            val mainDoc = resolveDoc(tree, name)
            val tmpDoc = resolveDoc(tree, "$name.mtmp")
            if (mainDoc == null && tmpDoc != null) {
                DocumentsContract.renameDocument(contentResolver, tmpDoc, name)
            } else if (mainDoc != null && tmpDoc != null) {
                DocumentsContract.deleteDocument(contentResolver, tmpDoc)
            }
        } catch (e: Exception) {
            Log.w(TAG, "recoverDoc $name failed", e)
        }
    }

    private fun readFile(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        val name = call.argument<String>("name")
        if (tree == null || name == null) {
            result.error("bad_args", "tree/name required", null)
            return
        }
        try {
            recoverDoc(tree, name)
            val doc = resolveDoc(tree, name) ?: run {
                result.success(null)
                return
            }
            contentResolver.openInputStream(doc)?.use { it.readBytes() }?.let {
                result.success(it)
            } ?: result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "readFile $name failed", e)
            result.error("read_failed", e.toString(), null)
        }
    }

    private fun readFilePrefix(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        val name = call.argument<String>("name")
        val limit = call.argument<Int>("limit") ?: 262144
        if (tree == null || name == null) {
            result.error("bad_args", "tree/name/limit required", null)
            return
        }
        try {
            recoverDoc(tree, name)
            val doc = resolveDoc(tree, name) ?: run {
                result.success(null)
                return
            }
            contentResolver.openInputStream(doc)?.use { input ->
                val buffer = ByteArray(limit)
                var total = 0
                while (total < limit) {
                    val read = input.read(buffer, total, limit - total)
                    if (read < 0) break
                    total += read
                }
                if (total == 0) {
                    result.success(null)
                } else {
                    result.success(buffer.copyOf(total))
                }
            } ?: result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "readFilePrefix $name failed", e)
            result.error("read_failed", e.toString(), null)
        }
    }

    private fun deleteFile(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        val name = call.argument<String>("name")
        if (tree == null || name == null) {
            result.error("bad_args", "tree/name required", null)
            return
        }
        try {
            val doc = resolveDoc(tree, name)
            result.success(
                doc != null && DocumentsContract.deleteDocument(contentResolver, doc)
            )
        } catch (e: Exception) {
            Log.e(TAG, "deleteFile $name failed", e)
            result.success(false)
        }
    }

    private fun listFiles(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        if (tree == null) {
            result.error("bad_args", "tree required", null)
            return
        }
        try {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val files = mutableListOf<String>()
            contentResolver.query(
                children,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(0) ?: continue
                    // Skip temp siblings left by writeFileAtomic; they are
                    // either recovered by recoverDoc or stale leftovers.
                    if (name.endsWith(".mtmp")) continue
                    files.add(name)
                }
            }
            result.success(files)
        } catch (e: Exception) {
            Log.e(TAG, "listFiles failed", e)
            result.error("list_failed", e.toString(), null)
        }
    }
}
