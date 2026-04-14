package com.example.hex_canvas_mobile

import android.app.DownloadManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val APK_FILENAME = "hex_canvas_update.apk"

class MainActivity : FlutterActivity() {

    private fun apkFile(): File {
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
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
                            // Delete any leftover APK so DownloadManager doesn't create
                            // a renamed file (hex_canvas_update-1.apk etc.)
                            apkFile().delete()
                            val dm =
                                getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            val req = DownloadManager.Request(Uri.parse(url))
                                .setTitle("Hex Canvas Update")
                                .setDescription("Downloading update…")
                                .setDestinationInExternalPublicDir(
                                    Environment.DIRECTORY_DOWNLOADS, APK_FILENAME
                                )
                                .setNotificationVisibility(
                                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                                )
                                .setMimeType("application/vnd.android.package-archive")
                                .addRequestHeader(
                                    "User-Agent",
                                    "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36"
                                )
                                .setAllowedOverMetered(true)
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
                        val dm =
                            getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
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
                        // The system-managed content URI (content://downloads/my_downloads/ID)
                        // is served by the system Downloads provider and is accessible to
                        // PackageManagerService without any FileProvider grants.
                        val localUri = cursor.getString(
                            cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
                        ) ?: ""
                        cursor.close()
                        result.success(
                            mapOf(
                                "status" to status,
                                "total" to total,
                                "downloaded" to downloaded,
                                "systemUri" to localUri
                            )
                        )
                    }

                    "checkInstallReady" -> {
                        val apk = apkFile()
                        val apkSize = if (apk.exists()) apk.length() else -1L

                        var apkVersionCode = -1L
                        var apkPackageName = ""
                        var installedVersionCode = -1L
                        if (apk.exists()) {
                            try {
                                val pi =
                                    packageManager.getPackageArchiveInfo(apk.absolutePath, 0)
                                if (pi != null) {
                                    apkPackageName = pi.packageName ?: ""
                                    apkVersionCode =
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                                            pi.longVersionCode
                                        else
                                            @Suppress("DEPRECATION") pi.versionCode.toLong()
                                }
                            } catch (_: Exception) {}
                        }
                        try {
                            val pi = packageManager.getPackageInfo(packageName, 0)
                            installedVersionCode =
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                                    pi.longVersionCode
                                else
                                    @Suppress("DEPRECATION") pi.versionCode.toLong()
                        } catch (_: Exception) {}

                        result.success(
                            mapOf(
                                "hasPermission" to canInstallPackages(),
                                "apkExists" to apk.exists(),
                                "apkPath" to apk.absolutePath,
                                "apkSize" to apkSize,
                                "apkVersionCode" to apkVersionCode,
                                "apkPackageName" to apkPackageName,
                                "installedVersionCode" to installedVersionCode
                            )
                        )
                    }

                    "installApk" -> {
                        val id = (call.argument<Any>("id") as? Number)?.toLong()
                        if (id == null) {
                            result.error("INVALID_ARG", "id is null", null)
                            return@setMethodCallHandler
                        }
                        try {
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
                            val dm =
                                getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            // getUriForDownloadedFile returns the correct content:// URI
                            // for the download — public_downloads for files in public
                            // storage, which PackageInstaller can read without grants.
                            val contentUri = dm.getUriForDownloadedFile(id)
                            if (contentUri == null) {
                                result.error(
                                    "NO_URI",
                                    "getUriForDownloadedFile returned null for id=$id",
                                    null
                                )
                                return@setMethodCallHandler
                            }
                            startActivity(
                                Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(
                                        contentUri,
                                        "application/vnd.android.package-archive"
                                    )
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                            )
                            // Return the URI string so Dart can log it
                            result.success(contentUri.toString())
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
