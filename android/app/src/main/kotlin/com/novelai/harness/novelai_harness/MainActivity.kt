package com.novelai.harness.novelai_harness

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// / 图片成品写入系统媒体库 (MediaStore)、自选 SAF 目录与剪贴板的原生通道。
// /
// / 作用域存储 (Android 10+) 下应用私有目录对其他应用不可见；
// / 经 MediaStore 写入公共 Pictures 目录的图片会被媒体库原生登记，
// / 相册与文件管理器立即可见，无需任何存储权限 (Q+)。
// /
// / 自选导出目录：ACTION_OPEN_DOCUMENT_TREE 由用户亲自挑选任意文件夹，
// / 授权持久化 (takePersistableUriPermission) 后重启仍生效；成品经
// / DocumentsContract 写入该目录树，自动创建命名模板子目录且不覆盖同名文件。
// /
// / 安卓系统剪贴板不支持裸位图字节，只能携带 content:// URI；
// / 复制图像先把字节写入应用缓存目录，经 FileProvider 暴露为 URI
// / 再放入剪贴板 (ClipData.newUri)，聊天/编辑类应用可直接粘贴。
class MainActivity : FlutterActivity() {
    private val channelName = "novelai_harness/media_store"
    private val clipboardDirName = "clipboard"

    // / SAF 目录选择结果回调 (pickDirectory 挂起等待本次选择)
    private var pendingPickResult: MethodChannel.Result? = null

    // / SAF 目录选择请求码 (onActivityResult 分流用；FlutterActivity 直接
    // / 继承 android.app.Activity 而非 ComponentActivity，没有 ActivityResult API)
    private val pickDirectoryRequestCode = 0x4E41

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> handleSaveImage(call, result)
                    "copyImage" -> handleCopyImage(call, result)
                    "pickDirectory" -> handlePickDirectory(result)
                    "getTreeInfo" -> handleTreeInfo(call, result)
                    "saveImageToTree" -> handleSaveImageToTree(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleSaveImage(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName") ?: ""
        val subDir = call.argument<String>("subDir") ?: ""
        if (bytes == null || bytes.isEmpty()) {
            result.error("EMPTY_BYTES", "图片字节为空", null)
            return
        }
        try {
            val location = saveImage(bytes, fileName, subDir)
            result.success(location)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message, null)
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    private fun handleCopyImage(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
            result.error("EMPTY_BYTES", "图片字节为空", null)
            return
        }
        try {
            val uri = writeClipboardCache(bytes)
            val clipboard = getSystemService(ClipboardManager::class.java)
            clipboard.setPrimaryClip(ClipData.newUri(contentResolver, "image", uri))
            result.success(true)
        } catch (e: Exception) {
            result.error("COPY_FAILED", e.message, null)
        }
    }

    // / 唤起系统目录选择器；用户取消返回 null，选中返回 {uri, name}。
    private fun handlePickDirectory(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("PICK_BUSY", "已有目录选择在进行中", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, pickDirectoryRequestCode)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("PICK_FAILED", e.message, null)
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickDirectoryRequestCode) return
        val result = pendingPickResult
        pendingPickResult = null
        if (resultCode != RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }
        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result?.success(
                mapOf("uri" to uri.toString(), "name" to treeDisplayName(uri)),
            )
        } catch (e: Exception) {
            result?.error("PICK_FAILED", e.message, null)
        }
    }

    // / 查询已保存目录的可用状态：授权失效 (卸载/清理授权) 返回 null。
    private fun handleTreeInfo(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val uriString = call.argument<String>("uri") ?: ""
        if (uriString.isBlank()) {
            result.success(null)
            return
        }
        try {
            val uri = Uri.parse(uriString)
            if (!hasPersistedPermission(uri)) {
                result.success(null)
                return
            }
            result.success(mapOf("uri" to uriString, "name" to treeDisplayName(uri)))
        } catch (e: Exception) {
            result.success(null)
        }
    }

    // / 把 PNG 字节写入自选 SAF 目录树的 relativePath (子目录按需创建)。
    private fun handleSaveImageToTree(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val bytes = call.argument<ByteArray>("bytes")
        val treeUri = call.argument<String>("treeUri") ?: ""
        val relativePath = call.argument<String>("relativePath") ?: ""
        if (bytes == null || bytes.isEmpty()) {
            result.error("EMPTY_BYTES", "图片字节为空", null)
            return
        }
        if (treeUri.isBlank()) {
            result.error("NO_DIRECTORY", "未选择导出目录", null)
            return
        }
        try {
            val uri = Uri.parse(treeUri)
            if (!hasPersistedPermission(uri)) {
                result.error("PERMISSION_DENIED", "目录授权已失效，请重新选择导出目录", null)
                return
            }
            val location = saveToDocumentTree(bytes, uri, relativePath)
            result.success(location)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message, null)
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    // / 把 PNG 字节写入公共图片媒体库，返回人类可读的展示路径。
    private fun saveImage(
        bytes: ByteArray,
        fileName: String,
        subDir: String,
    ): String {
        val cleanName =
            sanitizeFileName(
                if (fileName.isBlank()) "image_${System.currentTimeMillis()}.png" else fileName,
            )
        val cleanSubDir = subDir.trim('/').replace('\\', '/')

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val relativePath =
                if (cleanSubDir.isBlank()) {
                    Environment.DIRECTORY_PICTURES
                } else {
                    "${Environment.DIRECTORY_PICTURES}/$cleanSubDir"
                }
            val values =
                ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, cleanName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            val resolver = contentResolver
            val uri =
                resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert 失败")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("无法打开媒体库输出流")
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            val update =
                ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                }
            resolver.update(uri, update, null, null)
            return if (cleanSubDir.isBlank()) {
                "${Environment.DIRECTORY_PICTURES}/$cleanName"
            } else {
                "${Environment.DIRECTORY_PICTURES}/$cleanSubDir/$cleanName"
            }
        }

        // Android 9 及以下：媒体库插入需要 WRITE_EXTERNAL_STORAGE 权限。
        // 权限缺失时明确报错，由 Dart 侧回退 SAF 单文件导出。
        if (checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("缺少存储权限 (WRITE_EXTERNAL_STORAGE)")
        }
        val dir =
            if (cleanSubDir.isBlank()) {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            } else {
                File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    cleanSubDir,
                )
            }
        dir.mkdirs()
        if (!dir.isDirectory) {
            throw IllegalStateException("无法创建公共图片目录")
        }
        val baseName = cleanName.removeSuffix(".png")
        val existingNames =
            dir
                .listFiles()
                ?.map { it.name }
                ?.toSet()
                .orEmpty()
        val candidate =
            generateSequence(0) { it + 1 }
                .map { index -> if (index == 0) cleanName else "${baseName}_$index.png" }
                .first { it !in existingNames }
        val target = File(dir, candidate)
        target.parentFile?.mkdirs()
        FileOutputStream(target).use { it.write(bytes) }
        android.media.MediaScannerConnection.scanFile(
            this,
            arrayOf(target.absolutePath),
            arrayOf("image/png"),
            null,
        )
        return target.absolutePath
    }

    // / SAF 目录树写入：relativePath 形如 "2026-09/model/name.png" (目录段按需创建)。
    // / 同名冲突由 DocumentsProvider 自动改名 ("name (1).png")，绝不覆盖。
    private fun saveToDocumentTree(
        bytes: ByteArray,
        treeUri: Uri,
        relativePath: String,
    ): String {
        val resolver = contentResolver
        var docUri =
            DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
        val segments = relativePath.replace('\\', '/').split('/').filter { it.isNotBlank() }
        for ((index, segment) in segments.withIndex()) {
            val isFile = index == segments.lastIndex
            if (isFile) {
                val fileUri =
                    DocumentsContract.createDocument(resolver, docUri, "image/png", segment)
                        ?: throw IllegalStateException("无法创建文件 $segment")
                resolver.openOutputStream(fileUri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("无法打开文件输出流")
                val finalName = queryDisplayName(fileUri) ?: segment
                return buildString {
                    append(treeDisplayName(treeUri))
                    append('/')
                    for (i in 0 until index) {
                        append(segments[i])
                        append('/')
                    }
                    append(finalName)
                }
            }
            val childUri = findChildDirectory(resolver, docUri, segment)
            docUri =
                childUri
                    ?: DocumentsContract.createDocument(
                        resolver,
                        docUri,
                        DocumentsContract.Document.MIME_TYPE_DIR,
                        segment,
                    )
                    ?: throw IllegalStateException("无法创建子目录 $segment")
        }
        throw IllegalArgumentException("导出路径为空")
    }

    // / 在文档目录下查找同名子目录，不存在返回 null。
    private fun findChildDirectory(
        resolver: android.content.ContentResolver,
        parentDocUri: Uri,
        name: String,
    ): Uri? {
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(
                parentDocUri,
                DocumentsContract.getDocumentId(parentDocUri),
            )
        resolver
            .query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    if (nameIndex >= 0 && cursor.getString(nameIndex) == name) {
                        val docId = cursor.getString(idIndex)
                        return DocumentsContract.buildDocumentUriUsingTree(parentDocUri, docId)
                    }
                }
            }
        return null
    }

    // / 查询文档的真实显示名 (SAF 重名自动改名后以它为准)。
    private fun queryDisplayName(docUri: Uri): String? =
        try {
            contentResolver
                .query(
                    docUri,
                    arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
        } catch (e: Exception) {
            null
        }

    // / 目录树的友好名称：优先 DocumentsProvider 显示名，回退 URI 尾段。
    private fun treeDisplayName(treeUri: Uri): String {
        try {
            val rootId = DocumentsContract.getTreeDocumentId(treeUri)
            val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId)
            queryDisplayName(rootUri)?.let { return it }
        } catch (e: Exception) {
            // 落到 URI 尾段回退
        }
        val lastSegment = treeUri.lastPathSegment ?: return "已选文件夹"
        val afterVolume = lastSegment.substringAfter(':', lastSegment)
        return if (afterVolume.isBlank()) "已选文件夹" else afterVolume
    }

    // / 授权是否仍然有效 (用户可能在系统设置里撤销了目录授权)。
    private fun hasPersistedPermission(uri: Uri): Boolean =
        contentResolver.persistedUriPermissions.any {
            it.uri.toString() == uri.toString() && it.isWritePermission
        }

    // / 复制图像专用缓存：写入字节并返回 FileProvider URI。
    // / 只保留最近 8 个文件，避免剪贴板临时图无限堆积。
    private fun writeClipboardCache(bytes: ByteArray): Uri {
        val dir = File(cacheDir, clipboardDirName)
        dir.mkdirs()
        val stale = dir.listFiles().orEmpty()
        stale.sortedByDescending { it.lastModified() }.drop(7).forEach { it.delete() }
        val file = File(dir, "image_${System.currentTimeMillis()}.png")
        file.writeBytes(bytes)
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
    }

    // / 净化文件名：去掉路径分隔符与非法字符，防止越出目标子目录。
    private fun sanitizeFileName(name: String): String {
        val cleaned = name.replace('/', '_').replace('\\', '_').trim()
        return if (cleaned.isBlank()) "image_${System.currentTimeMillis()}.png" else cleaned
    }
}
