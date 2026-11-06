package com.weddingvideoshare.app

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "wedding_video_share/persistent_upload"
    private val pickRequestCode = 7412
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pickerOrderId: String = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickVideos" -> {
                        if (pendingPickerResult != null) {
                            result.error("PICK_IN_PROGRESS", "A video picker is already open.", null)
                        } else {
                            pendingPickerResult = result
                            pickerOrderId = call.argument<String>("orderId") ?: ""
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "video/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }
                            startActivityForResult(intent, pickRequestCode)
                        }
                    }
                    "listPending" -> result.success(readPending())
                    "readChunk" -> {
                        try {
                            val uri = Uri.parse(call.argument<String>("uri") ?: error("Missing URI"))
                            val offset = call.argument<Number>("offset")?.toLong() ?: error("Missing offset")
                            val length = call.argument<Number>("length")?.toInt() ?: error("Missing length")
                            require(offset >= 0 && length in 1..(8 * 1024 * 1024)) { "Invalid chunk range" }
                            val pfd = contentResolver.openFileDescriptor(uri, "r")
                                ?: error("Android could not open this video. Please select it again.")
                            val bytes = pfd.use { descriptor ->
                                FileInputStream(descriptor.fileDescriptor).use { stream ->
                                    val channel = stream.channel
                                    channel.position(offset)
                                    val buffer = java.nio.ByteBuffer.allocate(length)
                                    while (buffer.hasRemaining()) {
                                        val count = channel.read(buffer)
                                        if (count < 0) break
                                    }
                                    buffer.array().copyOf(buffer.position())
                                }
                            }
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("READ_FAILED", e.message ?: "Could not read this video.", null)
                        }
                    }
                    "removePending" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        val items = readPending().filterNot { it.optString("uri") == uri }
                        writePending(items)
                        try {
                            contentResolver.releasePersistableUriPermission(Uri.parse(uri), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        } catch (_: Exception) { }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequestCode) return
        val callback = pendingPickerResult
        pendingPickerResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            callback?.success(emptyList<Map<String, Any>>())
            return
        }
        try {
            val uris = mutableListOf<Uri>()
            data.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            } ?: data.data?.let { uris.add(it) }
            val existing = readPending()
            val output = mutableListOf<Map<String, Any>>()
            for (uri in uris.distinct()) {
                try {
                    contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (_: Exception) { }
                val meta = describe(uri)
                if (meta["size"] as Long > 0L) {
                    val record = JSONObject().apply {
                        put("uri", uri.toString())
                        put("name", meta["name"])
                        put("size", meta["size"])
                        put("mime", meta["mime"])
                        put("orderId", pickerOrderId)
                    }
                    if (existing.none { it.optString("uri") == uri.toString() }) existing.add(record)
                    output.add(mapOf(
                        "uri" to uri.toString(),
                        "name" to (meta["name"] ?: "video"),
                        "size" to (meta["size"] ?: 0L),
                        "mime" to (meta["mime"] ?: "video/*"),
                        "orderId" to pickerOrderId
                    ))
                }
            }
            writePending(existing)
            callback?.success(output)
        } catch (e: Exception) {
            callback?.error("PICK_FAILED", e.message ?: "Could not save video access.", null)
        }
    }

    private fun describe(uri: Uri): Map<String, Any> {
        var name = "video"
        var size = 0L
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIndex >= 0) name = it.getString(nameIndex) ?: name
                    if (sizeIndex >= 0) size = it.getLong(sizeIndex)
                }
            }
        } catch (_: Exception) { }
        val mime = contentResolver.getType(uri) ?: "video/*"
        return mapOf("name" to name, "size" to size, "mime" to mime)
    }

    private fun readPending(): MutableList<JSONObject> {
        val raw = getSharedPreferences("persistent_uploads", MODE_PRIVATE).getString("items", "[]") ?: "[]"
        val array = JSONArray(raw)
        val result = mutableListOf<JSONObject>()
        for (i in 0 until array.length()) result.add(array.getJSONObject(i))
        return result
    }

    private fun writePending(items: List<JSONObject>) {
        val array = JSONArray()
        items.forEach { array.put(it) }
        getSharedPreferences("persistent_uploads", MODE_PRIVATE).edit().putString("items", array.toString()).apply()
    }
}
