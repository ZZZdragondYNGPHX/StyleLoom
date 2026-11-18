package com.styleloom.styleloom_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.styleloom/platform"
    private var channel: MethodChannel? = null
    private var pendingSharedPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharedPath = extractSharedFile(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedFile" -> {
                    val path = pendingSharedPath
                    pendingSharedPath = null
                    result.success(path)
                }
                "shareFile" -> {
                    val filePath = call.argument<String>("path")
                    val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Empty share path", null)
                    } else {
                        try {
                            shareLocalFile(filePath, mime)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = extractSharedFile(intent)
        if (path != null) {
            if (channel != null) {
                channel?.invokeMethod("onSharedFile", path)
            } else {
                pendingSharedPath = path
            }
        }
    }

    private fun extractSharedFile(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val inbox = File(cacheDir, "shared_inbox")
        if (!inbox.exists()) inbox.mkdirs()

        val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

        if (uri != null) {
            var target: File? = null
            return try {
                val name = resolveFileName(uri)?.substringAfterLast('/')?.substringAfterLast('\\')
                    ?.takeIf { it.isNotBlank() } ?: "shared"
                val outputFile = File(inbox, "${System.nanoTime()}_$name")
                target = outputFile
                val inputStream = contentResolver.openInputStream(uri) ?: return null
                inputStream.use { input ->
                    FileOutputStream(outputFile).use { output ->
                        input.copyTo(output)
                    }
                }
                outputFile.absolutePath
            } catch (_: Exception) {
                target?.delete()
                null
            }
        }

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!text.isNullOrBlank() && text.trimStart().startsWith("{")) {
            val outFile = File(inbox, "shared_${System.currentTimeMillis()}.json")
            return try {
                outFile.writeText(text, Charsets.UTF_8)
                outFile.absolutePath
            } catch (_: Exception) {
                outFile.delete()
                null
            }
        }
        return null
    }

    private fun resolveFileName(uri: Uri): String? {
        try {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) {
                return cursor.getString(idx)
            }
        }
        } catch (_: Exception) {
            // Some providers allow reading a stream but do not expose metadata.
        }
        return uri.lastPathSegment
    }

    private fun shareLocalFile(path: String, mime: String) {
        val file = File(path)
        require(file.isFile) { "Share file does not exist" }
        val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(shareIntent, "分享 .slpack 备份包"))
    }
}
