package com.nzwx.nzdownloader

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.nzwx.nzdownloader/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                if (path.isNullOrBlank() || name.isNullOrBlank()) {
                    result.error("ARGS", "Missing file arguments", null)
                    return@setMethodCallHandler
                }

                try {
                    val source = File(path)
                    if (!source.exists()) {
                        result.error("FILE", "Temporary file not found", null)
                        return@setMethodCallHandler
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val values = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, name)
                            put(MediaStore.Downloads.MIME_TYPE, mime)
                            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/NzTools")
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                        val resolver = contentResolver
                        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            ?: throw Exception("Could not create Downloads entry")
                        try {
                            resolver.openOutputStream(uri)?.use { output ->
                                source.inputStream().use { input -> input.copyTo(output, bufferSize = 256 * 1024) }
                            } ?: throw Exception("Could not open output stream")
                            values.clear()
                            values.put(MediaStore.Downloads.IS_PENDING, 0)
                            resolver.update(uri, values, null, null)
                            result.success("Downloads/NzTools/$name")
                        } catch (e: Exception) {
                            resolver.delete(uri, null, null)
                            throw e
                        }
                    } else {
                        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS + "/NzTools")
                        if (!dir.exists()) dir.mkdirs()
                        val target = File(dir, name)
                        source.copyTo(target, overwrite = true)
                        result.success(target.absolutePath)
                    }
                } catch (e: Exception) {
                    result.error("SAVE", e.message, null)
                }
            }
    }
}
