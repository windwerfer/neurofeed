package com.example.muse_ml

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import android.util.Log
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "muse_ml/saf"
        private const val REQ_PICK_DIR = 7401
        private const val REQ_PICK_FILE = 7402
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
        if (requestCode == REQ_PICK_DIR || requestCode == REQ_PICK_FILE) {
            val pending = pendingResult ?: return
            pendingResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }
            val uri = data.data!!
            if (requestCode == REQ_PICK_DIR) {
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
            } else {
                pending.success(uri.toString())
            }
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
            "pickFile" -> {
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/octet-stream"))
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivityForResult(intent, REQ_PICK_FILE)
            }
            "copyUriToCache" -> copyUriToCache(call, result)
            "copySafFileToCache" -> copySafFileToCache(call, result)
            "ensureDir" -> { result.success(null); }
            "writeFile" -> writeFile(call, result)
            "writeFileAtomic" -> writeFileAtomic(call, result)
            "readFile" -> readFile(call, result)
            "readFilePrefix" -> readFilePrefix(call, result)
            "deleteFile" -> deleteFile(call, result)
            "listFilesMeta" -> listFilesMeta(call, result)
            else -> result.notImplemented()
        }
    }

    private fun treeUri(call: MethodCall): Uri? {
        val tree = call.argument<String>("tree") ?: return null
        return Uri.parse(tree)
    }

    /// Document URI of the tree root itself.
    private fun treeRootDoc(tree: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(
        tree, DocumentsContract.getTreeDocumentId(tree)
    )

    /// Resolve a child document by its display [name] inside [parent].
    /// Returns the document URI, or null if no child with that name exists.
    /// [parent] may be the tree root or any subdirectory document.
    ///
    /// `buildDocumentUriUsingTree(tree, name)` cannot be used directly: it
    /// expects the child's *document ID* (e.g. `primary:Med fed/session_x`),
    /// not the bare display name, so it must be looked up via the query.
    private fun resolveDoc(tree: Uri, parent: Uri, name: String): Uri? {
        val parentId = DocumentsContract.getDocumentId(parent)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
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

    /// Resolve the (possibly nested) directory path [dir] below the tree
    /// root, creating missing segments. Returns null only on provider failure.
    private fun resolveOrCreateDir(tree: Uri, dir: String): Uri? {
        var parent = treeRootDoc(tree)
        for (segment in dir.split("/")) {
            if (segment.isEmpty()) continue
            val existing = resolveDoc(tree, parent, segment)
            parent = existing ?: DocumentsContract.createDocument(
                contentResolver, parent, DocumentsContract.Document.MIME_TYPE_DIR, segment
            ) ?: return null
        }
        return parent
    }

    /// Parent document for a (possibly nested) write: the tree root, or the
    /// `export` subdir when [dir] is set.
    private fun writeParent(tree: Uri, dir: String?): Uri? {
        if (dir == null || dir.isEmpty()) {
            return treeRootDoc(tree)
        }
        return resolveOrCreateDir(tree, dir)
    }

    private fun writeFile(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        val name = call.argument<String>("name")
        val bytes = call.argument<ByteArray>("bytes")
        val dir = call.argument<String>("dir")
        if (tree == null || name == null || bytes == null) {
            result.error("bad_args", "tree/name/bytes required", null)
            return
        }
        try {
            val parent = writeParent(tree, dir) ?: run {
                result.error("open_failed", "could not open $dir", null)
                return
            }
            var doc = resolveDoc(tree, parent, name)
            if (doc == null) {
                // Document doesn't exist yet — create it first, then write.
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
        val dir = call.argument<String>("dir")
        if (tree == null || name == null || bytes == null) {
            result.error("bad_args", "tree/name/bytes required", null)
            return
        }
        try {
            val parent = writeParent(tree, dir) ?: run {
                result.error("open_failed", "could not open $dir", null)
                return
            }
            val tmpName = "$name.mtmp"
            // 1. Write the full new content to a sibling temp document.
            var tmpDoc = resolveDoc(tree, parent, tmpName)
            if (tmpDoc == null) {
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
            val oldDoc = resolveDoc(tree, parent, name)
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
            val root = treeRootDoc(tree)
            val mainDoc = resolveDoc(tree, root, name)
            val tmpDoc = resolveDoc(tree, root, "$name.mtmp")
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
            val doc = resolveDoc(tree, treeRootDoc(tree), name) ?: run {
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
            val doc = resolveDoc(tree, treeRootDoc(tree), name) ?: run {
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
            val doc = resolveDoc(tree, treeRootDoc(tree), name)
            result.success(
                doc != null && DocumentsContract.deleteDocument(contentResolver, doc)
            )
        } catch (e: Exception) {
            Log.e(TAG, "deleteFile $name failed", e)
            result.success(false)
        }
    }

    private fun listFilesMeta(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        if (tree == null) {
            result.error("bad_args", "tree required", null)
            return
        }
        try {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            // First pass: heal any orphaned .mtmp siblings left by an
            // interrupted writeFileAtomic so a recovered session reappears in
            // the listing instead of staying invisible until some other op
            // reads the exact same name.
            contentResolver.query(
                children,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(0) ?: continue
                    if (name.endsWith(".mtmp")) {
                        recoverDoc(tree, name.removeSuffix(".mtmp"))
                    }
                }
            }

            // Second pass: list the healed set with last-modified timestamps
            // (used by the metadata cache to detect changed files). Any .mtmp
            // still present is a stale leftover that recoverDoc could not
            // resolve and is skipped.
            val files = mutableListOf<Map<String, Any?>>()
            contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                ),
                null, null, null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(0) ?: continue
                    if (name.endsWith(".mtmp")) continue
                    files.add(
                        mapOf(
                            "name" to name,
                            "mtime" to cursor.getLong(1),
                        )
                    )
                }
            }
            result.success(files)
        } catch (e: Exception) {
            Log.e(TAG, "listFilesMeta failed", e)
            result.error("list_failed", e.toString(), null)
        }
    }

    private fun copyUriToCache(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri")
        val destName = call.argument<String>("destName")
        if (uriString == null || destName == null) {
            result.error("bad_args", "uri/destName required", null)
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val uri = Uri.parse(uriString)
                val cacheFile = File(cacheDir, destName)

                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(cacheFile).use { output ->
                        input.copyTo(output, bufferSize = 64 * 1024)
                    }
                } ?: run {
                    withContext(Dispatchers.Main) { result.error("open_failed", "could not open $uriString", null) }
                    return@launch
                }

                withContext(Dispatchers.Main) { result.success(cacheFile.absolutePath) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("copy_failed", e.toString(), null) }
            }
        }
    }

    private fun copySafFileToCache(call: MethodCall, result: Result) {
        val tree = treeUri(call)
        val name = call.argument<String>("name")
        val destName = call.argument<String>("destName")
        if (tree == null || name == null || destName == null) {
            result.error("bad_args", "tree/name/destName required", null)
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val doc = resolveDoc(tree, treeRootDoc(tree), name)
                if (doc == null) {
                    withContext(Dispatchers.Main) { result.error("not_found", "could not resolve $name", null) }
                    return@launch
                }

                val cacheFile = File(cacheDir, destName)

                contentResolver.openInputStream(doc)?.use { input ->
                    FileOutputStream(cacheFile).use { output ->
                        input.copyTo(output, bufferSize = 64 * 1024)
                    }
                } ?: run {
                    withContext(Dispatchers.Main) { result.error("open_failed", "could not open $name", null) }
                    return@launch
                }

                withContext(Dispatchers.Main) { result.success(cacheFile.absolutePath) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("copy_failed", e.toString(), null) }
            }
        }
    }
}
