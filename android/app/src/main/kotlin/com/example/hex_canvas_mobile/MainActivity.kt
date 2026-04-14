package com.example.hex_canvas_mobile

import android.app.DownloadManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
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
                            // Delete any leftover APK so DownloadManager doesn't create
                            // a renamed file (hex_canvas_update-1.apk etc.) which would
                            // cause FileProvider to serve the old file on install.
                            apkFile()?.delete()
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
                                // GitHub release assets redirect to CDN; a browser-like UA
                                // prevents some CDN nodes from returning an error page.
                                .addRequestHeader(
                                    "User-Agent",
                                    "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36"
                                )
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
                        val apkSize = if (apk?.exists() == true) apk.length() else -1L
                        result.success(
                            mapOf(
                                "hasPermission" to canInstallPackages(),
                                "apkExists" to (apk?.exists() ?: false),
                                "apkPath" to (apk?.absolutePath ?: ""),
                                "apkSize" to apkSize
                            )
                        )
                    }

                    "installApk" -> {
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

                        // Use PackageInstaller API: stream APK bytes directly into a system
                        // session so the installer never needs to access a FileProvider URI
                        // (content:// URI grants don't reach the system installer process on
                        // many Android versions, causing silent failure after user confirms).
                        Thread {
                            try {
                                val installer = packageManager.packageInstaller
                                val params = PackageInstaller.SessionParams(
                                    PackageInstaller.SessionParams.MODE_FULL_INSTALL
                                )
                                val sessionId = installer.createSession(params)
                                installer.openSession(sessionId).use { session ->
                                    apk.inputStream().use { input ->
                                        session.openWrite("update", 0L, apk.length())
                                            .use { output ->
                                                input.copyTo(output)
                                                session.fsync(output)
                                            }
                                    }
                                    val piFlags =
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                                            PendingIntent.FLAG_UPDATE_CURRENT or
                                                    PendingIntent.FLAG_MUTABLE
                                        else PendingIntent.FLAG_UPDATE_CURRENT
                                    val pi = PendingIntent.getActivity(
                                        applicationContext, sessionId,
                                        Intent(applicationContext, MainActivity::class.java)
                                            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                                        piFlags
                                    )
                                    session.commit(pi.intentSender)
                                }
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("INSTALL_ERROR", e.message, null)
                            }
                        }.start()
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
