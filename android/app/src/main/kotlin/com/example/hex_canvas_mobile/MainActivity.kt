package com.example.hex_canvas_mobile

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val APK_FILENAME = "hex_canvas_update.apk"

class MainActivity : FlutterActivity() {

    private fun apkFile(): File? {
        val dir = applicationContext.getExternalFilesDir(null) ?: return null
        return File(dir, APK_FILENAME)
    }

    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                packageManager.canRequestPackageInstalls()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hex_canvas/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startDownload" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("INVALID_ARG", "url is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val dir = applicationContext.getExternalFilesDir(null)
                            if (dir == null) {
                                result.error("NO_STORAGE", "External storage unavailable", null)
                                return@setMethodCallHandler
                            }
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            val req = DownloadManager.Request(Uri.parse(url))
                                .setTitle("Hex Canvas Update")
                                .setDescription("Downloading update…")
                                .setDestinationInExternalFilesDir(
                                    applicationContext, null, APK_FILENAME
                                )
                                .setNotificationVisibility(
                                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                                )
                                .setMimeType("application/vnd.android.package-archive")
                            result.success(dm.enqueue(req))
                        } catch (e: Exception) {
                            result.error("DOWNLOAD_ERROR", e.message, null)
                        }
                    }

                    "getDownloadStatus" -> {
                        val id = (call.argument<Any>("id") as? Number)?.toLong()
                        if (id == null) {
                            result.error("INVALID_ARG", "id is null", null)
                            return@setMethodCallHandler
                        }
                        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                        val cursor = dm.query(DownloadManager.Query().setFilterById(id))
                        if (!cursor.moveToFirst()) {
                            cursor.close()
                            result.error("NOT_FOUND", "Download not found", null)
                            return@setMethodCallHandler
                        }
                        val status = cursor.getInt(
                            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                        )
                        val total = cursor.getLong(
                            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                        )
                        val downloaded = cursor.getLong(
                            cursor.getColumnIndexOrThrow(
                                DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR
                            )
                        )
                        cursor.close()
                        // Return the canonical apk path so Flutter always holds the exact path
                        // that FileProvider will use — avoids /storage/emulated/0 vs /sdcard
                        // symlink mismatches.
                        val apk = apkFile()
                        result.success(
                            mapOf(
                                "status" to status,
                                "total" to total,
                                "downloaded" to downloaded,
                                "filePath" to (apk?.absolutePath ?: "")
                            )
                        )
                    }

                    // Returns a map with install-readiness info so Flutter can show
                    // a diagnostic message before the user even taps Install.
                    "checkInstallReady" -> {
                        val apk = apkFile()
                        result.success(
                            mapOf(
                                "hasPermission" to canInstallPackages(),
                                "apkExists" to (apk?.exists() ?: false),
                                "apkPath" to (apk?.absolutePath ?: "")
                            )
                        )
                    }

                    "installApk" -> {
                        try {
                            val apk = apkFile()
                            if (apk == null) {
                                result.error("NO_STORAGE", "External storage unavailable", null)
                                return@setMethodCallHandler
                            }
                            if (!apk.exists()) {
                                result.error(
                                    "NOT_FOUND",
                                    "APK not found at ${apk.absolutePath} — try downloading again.",
                                    null
                                )
                                return@setMethodCallHandler
                            }

                            // On Android 8+ the user must enable "Install unknown apps" for
                            // this specific app.  Open the exact Settings screen for it so the
                            // user can grant permission, then tap Install again.
                            if (!canInstallPackages()) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName")
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.error(
                                    "NEED_PERMISSION",
                                    "Разрешите установку из неизвестных источников для Hex Canvas в открывшихся настройках, затем нажмите Install снова.",
                                    null
                                )
                                return@setMethodCallHandler
                            }

                            val uri = FileProvider.getUriForFile(
                                applicationContext,
                                "${packageName}.fileProvider",
                                apk
                            )
                            startActivity(
                                Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
