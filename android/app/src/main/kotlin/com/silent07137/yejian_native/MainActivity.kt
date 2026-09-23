package com.silent07137.yejian_native

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.FileInputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.silent07137.yejian/document"
    private val saveRequestCode = 4107
    private val linkDirectoryRequestCode = 4108
    private val preferencesName = "yejian_document_locations"
    private val exportDirectoryKey = "export_tree_uri"
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLinkedExportDirectory" -> result.success(linkedDirectoryUri()?.toString())
                    "clearLinkedExportDirectory" -> clearLinkedDirectory(result)
                    "linkExportDirectory" -> linkExportDirectory(result)
                    "saveDocument" -> saveDocument(call, result)
                    "openExternalUrl" -> openExternalUrl(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openExternalUrl(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        val value = call.argument<String>("url")
        val uri = value?.let(Uri::parse)
        if (uri == null || uri.scheme?.lowercase() !in setOf("http", "https")) {
            result.success(false)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        } catch (_: SecurityException) {
            result.success(false)
        }
    }

    private fun preferences() = getSharedPreferences(preferencesName, MODE_PRIVATE)

    private fun linkedDirectoryUri(): Uri? {
        val value = preferences().getString(exportDirectoryKey, null) ?: return null
        return Uri.parse(value)
    }

    private fun linkExportDirectory(result: MethodChannel.Result) {
        if (!beginPending(result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        startActivityForResult(intent, linkDirectoryRequestCode)
    }

    private fun clearLinkedDirectory(result: MethodChannel.Result) {
        linkedDirectoryUri()?.let { uri ->
            try {
                contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: SecurityException) {
                // The system may already have revoked the grant.
            }
        }
        preferences().edit().remove(exportDirectoryKey).apply()
        result.success(true)
    }

    private fun saveDocument(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        if (!beginPending(result)) return
        val sourcePath = call.argument<String>("sourcePath")
        val name = call.argument<String>("name")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (sourcePath.isNullOrBlank() || name.isNullOrBlank()) {
            finishPendingError("invalid_arguments", "缺少待保存文件信息")
            return
        }
        if (!File(sourcePath).isFile) {
            finishPendingError("source_missing", "待保存的临时文件不存在")
            return
        }
        pendingSourcePath = sourcePath
        val linkedDirectory = linkedDirectoryUri()
        if (linkedDirectory != null) {
            saveIntoLinkedDirectory(linkedDirectory, name, mimeType, sourcePath)
            return
        }
        launchCreateDocument(name, mimeType)
    }

    private fun beginPending(result: MethodChannel.Result): Boolean {
        if (pendingResult != null) {
            result.error("operation_in_progress", "已有文件操作正在进行", null)
            return false
        }
        pendingResult = result
        return true
    }

    private fun launchCreateDocument(name: String, mimeType: String) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, name)
        }
        startActivityForResult(intent, saveRequestCode)
    }

    private fun saveIntoLinkedDirectory(
        treeUri: Uri,
        requestedName: String,
        mimeType: String,
        sourcePath: String
    ) {
        Thread {
            try {
                val parentDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
                val parentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    parentDocumentId
                )
                val displayName = availableDisplayName(treeUri, parentDocumentId, requestedName)
                val target = requireNotNull(
                    DocumentsContract.createDocument(
                        contentResolver,
                        parentUri,
                        mimeType,
                        displayName
                    )
                ) { "无法在已关联目录中创建文件" }
                copyToUri(sourcePath, target)
                runOnUiThread {
                    finishPendingSuccess(
                        mapOf(
                            "status" to "saved",
                            "uri" to target.toString(),
                            "name" to displayName,
                            "linkedDirectory" to true
                        )
                    )
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (error is SecurityException) {
                        preferences().edit().remove(exportDirectoryKey).apply()
                    }
                    finishPendingSuccess(
                        mapOf(
                            "status" to "failed",
                            "message" to if (error is SecurityException) {
                                "导出目录授权已失效，请重新关联目录"
                            } else {
                                error.localizedMessage ?: "无法写入已关联目录"
                            }
                        )
                    )
                }
            }
        }.start()
    }

    private fun availableDisplayName(treeUri: Uri, parentId: String, requestedName: String): String {
        val names = mutableSetOf<String>()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) names.add(cursor.getString(0))
        }
        if (!names.contains(requestedName)) return requestedName
        val dot = requestedName.lastIndexOf('.')
        val base = if (dot > 0) requestedName.substring(0, dot) else requestedName
        val extension = if (dot > 0) requestedName.substring(dot) else ""
        var number = 2
        while (names.contains("$base ($number)$extension")) number++
        return "$base ($number)$extension"
    }

    private fun copyToUri(sourcePath: String, target: Uri) {
        contentResolver.openOutputStream(target, "w").use { output ->
            requireNotNull(output) { "系统未提供可写入的文档" }
            FileInputStream(sourcePath).use { input ->
                input.copyTo(output)
                output.flush()
            }
        }
    }

    private fun finishPendingSuccess(value: Any?) {
        val result = pendingResult
        pendingResult = null
        pendingSourcePath = null
        result?.success(value)
    }

    private fun finishPendingError(code: String, message: String) {
        val result = pendingResult
        pendingResult = null
        pendingSourcePath = null
        result?.error(code, message, null)
    }

    @Deprecated("Deprecated in Android SDK; retained for FlutterActivity result routing")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            linkDirectoryRequestCode -> handleLinkedDirectoryResult(resultCode, data)
            saveRequestCode -> handleSaveResult(resultCode, data)
        }
    }

    private fun handleLinkedDirectoryResult(resultCode: Int, data: Intent?) {
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            finishPendingSuccess(mapOf("status" to "cancelled"))
            return
        }
        try {
            val flags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, flags)
            preferences().edit().putString(exportDirectoryKey, uri.toString()).apply()
            finishPendingSuccess(mapOf("status" to "linked", "uri" to uri.toString()))
        } catch (error: Exception) {
            finishPendingSuccess(
                mapOf(
                    "status" to "failed",
                    "message" to (error.localizedMessage ?: "无法保留目录授权")
                )
            )
        }
    }

    private fun handleSaveResult(resultCode: Int, data: Intent?) {
        val target = data?.data
        val sourcePath = pendingSourcePath
        if (resultCode != Activity.RESULT_OK || target == null) {
            finishPendingSuccess(mapOf("status" to "cancelled"))
            return
        }
        try {
            copyToUri(requireNotNull(sourcePath), target)
            finishPendingSuccess(mapOf("status" to "saved", "uri" to target.toString()))
        } catch (error: Exception) {
            finishPendingSuccess(
                mapOf(
                    "status" to "failed",
                    "message" to (error.localizedMessage ?: "写入系统文档失败")
                )
            )
        }
    }
}
