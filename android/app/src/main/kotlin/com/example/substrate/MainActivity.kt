package com.example.substrate

import android.app.DownloadManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val APK_FILENAME = "substrate_update.apk"
private const val ACTION_INSTALL_STATUS = "com.example.substrate.INSTALL_STATUS"

// Receives the PackageInstaller broadcast and starts the confirmation activity.
// STATUS_PENDING_USER_ACTION carries the real "Do you want to install?" intent
// that we must start to make the dialog appear.
class InstallStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_INSTALL_STATUS) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirmIntent =
                intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
            context.startActivity(confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "substrate/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startDownload" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("INVALID_ARG", "url is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            apkFile().delete()
                            val dm =
                                getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            val req = DownloadManager.Request(Uri.parse(url))
                                .setTitle("Substrate Update")
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
                        cursor.close()
                        result.success(
                            mapOf(
                                "status" to status,
                                "total" to total,
                                "downloaded" to downloaded,
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
                        if (!canInstallPackages()) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.error(
                                "NEED_PERMISSION",
                                "Разрешите установку из неизвестных источников в открывшихся настройках, затем нажмите Install снова.",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        val apk = apkFile()
                        if (!apk.exists()) {
                            result.error("NO_FILE", "APK not found: ${apk.absolutePath}", null)
                            return@setMethodCallHandler
                        }
                        // Use PackageInstaller session API: we read the APK ourselves and
                        // write it to the session, so PackageManagerService never needs a
                        // URI grant — this avoids the "exposed beyond app" / parse failure
                        // that affects content:// URI approaches.
                        // The broadcast STATUS_PENDING_USER_ACTION delivers the real
                        // confirmation-dialog intent which InstallStatusReceiver must start.
                        Thread {
                            try {
                                val pi = packageManager.packageInstaller
                                val params = PackageInstaller.SessionParams(
                                    PackageInstaller.SessionParams.MODE_FULL_INSTALL
                                )
                                val sessionId = pi.createSession(params)
                                pi.openSession(sessionId).use { session ->
                                    session.openWrite("base.apk", 0, apk.length()).use { out ->
                                        apk.inputStream().use { it.copyTo(out) }
                                        session.fsync(out)
                                    }
                                    val broadcastIntent =
                                        Intent(ACTION_INSTALL_STATUS).setPackage(packageName)
                                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                                            PendingIntent.FLAG_MUTABLE
                                        else 0
                                    val pending = PendingIntent.getBroadcast(
                                        applicationContext, sessionId, broadcastIntent, flags
                                    )
                                    session.commit(pending.intentSender)
                                }
                                result.success("session:$sessionId")
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
