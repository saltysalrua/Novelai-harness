package com.novelai.harness.novelai_harness

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// / 图片成品写入系统媒体库 (MediaStore) 与复制到剪贴板的原生通道。
// /
// / 作用域存储 (Android 10+) 下应用私有目录对其他应用不可见；
// / 经 MediaStore 写入公共 Pictures 目录的图片会被媒体库原生登记，
// / 相册与文件管理器立即可见，无需任何存储权限 (Q+)。
// /
// / 安卓系统剪贴板不支持裸位图字节，只能携带 content:// URI；
// / 复制图像先把字节写入应用缓存目录，经 FileProvider 暴露为 URI
// / 再放入剪贴板 (ClipData.newUri)，聊天/编辑类应用可直接粘贴。
class MainActivity : FlutterActivity() {
    private val channelName = "novelai_harness/media_store"
    private val clipboardDirName = "clipboard"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> handleSaveImage(call, result)
                    "copyImage" -> handleCopyImage(call, result)
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
        val existingNames = dir.listFiles()?.map { it.name }?.toSet().orEmpty()
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

    // / 复制图像专用缓存：写入字节并返回 FileProvider URI。
    // / 只保留最近 8 个文件，避免剪贴板临时图无限堆积。
    private fun writeClipboardCache(bytes: ByteArray): android.net.Uri {
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
