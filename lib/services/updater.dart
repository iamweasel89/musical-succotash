import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// ── Update state ───────────────────────────────────────────────────────────
enum UpdState { idle, checking, upToDate, available, downloading, ready, error }

class InstallReadiness {
  final bool hasPermission;
  final bool apkExists;
  final String apkPath;
  final int apkSize; // bytes; -1 if not found
  const InstallReadiness({
    required this.hasPermission,
    required this.apkExists,
    required this.apkPath,
    this.apkSize = -1,
  });
  bool get ok => hasPermission && apkExists;
}

class UpdateInfo {
  final int latestBuild;
  final String downloadUrl;
  final String releaseName;
  const UpdateInfo({
    required this.latestBuild,
    required this.downloadUrl,
    required this.releaseName,
  });
}

// ── Updater singleton ──────────────────────────────────────────────────────
class AppUpdater {
  static const _releasesLatest =
      'https://github.com/iamweasel89/musical-succotash/releases/latest';
  static const _repoBase =
      'https://github.com/iamweasel89/musical-succotash';
  static const _channel = MethodChannel('hex_canvas/updater');

  // ── Persistent state ──────────────────────────────────────────────────────
  static UpdState state = UpdState.idle;
  static String message = '';
  static double progress = 0;
  static UpdateInfo? updateInfo;
  static File? downloadedFile;
  static InstallReadiness? installReadiness;
  static int _installedBuild = 0;

  // ── In-app log ────────────────────────────────────────────────────────────
  static final List<String> log = [];
  static bool showLog = false;

  static void _log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    log.add('[$ts] $msg');
    if (log.length > 200) log.removeAt(0);
    _notify();
  }

  static void clearLog() {
    log.clear();
    _notify();
  }

  // ── Listeners ─────────────────────────────────────────────────────────────
  static final List<void Function()> _listeners = [];
  static void addListener(void Function() fn) => _listeners.add(fn);
  static void removeListener(void Function() fn) => _listeners.remove(fn);
  static void _notify() {
    for (final fn in List.of(_listeners)) fn();
  }

  static void dismissInstaller() {
    state = UpdState.idle;
    message = '';
    downloadedFile = null;
    installReadiness = null;
    _notify();
  }

  /// Called when the settings sheet reopens to resume any in-progress state.
  /// Download is a single streaming operation, so nothing needs to be restarted.
  static void resumePollingIfNeeded() {
    // No-op: streaming download doesn't use background polling.
  }

  static Future<void> checkInstallReady() async {
    _log('checkInstallReady: calling native…');
    try {
      final raw = await _channel.invokeMethod<Map>('checkInstallReady');
      if (raw == null) {
        _log('checkInstallReady: native returned null');
        return;
      }
      installReadiness = InstallReadiness(
        hasPermission: raw['hasPermission'] as bool? ?? false,
        apkExists: raw['apkExists'] as bool? ?? false,
        apkPath: raw['apkPath'] as String? ?? '',
        apkSize: (raw['apkSize'] as num?)?.toInt() ?? -1,
      );
      final apkVc = (raw['apkVersionCode'] as num?)?.toInt() ?? -1;
      final instVc = (raw['installedVersionCode'] as num?)?.toInt() ?? -1;
      final apkPkg = raw['apkPackageName'] as String? ?? '';
      _log('checkInstallReady: hasPermission=${installReadiness!.hasPermission}'
          ' apkExists=${installReadiness!.apkExists}'
          ' size=${installReadiness!.apkSize}B');
      _log('checkInstallReady: apk.pkg=$apkPkg'
          ' apk.versionCode=$apkVc'
          ' installed.versionCode=$instVc'
          ' canUpdate=${apkVc > instVc}');
    } catch (e) {
      _log('checkInstallReady: error — $e');
    }
    _notify();
  }

  // ── Public actions ────────────────────────────────────────────────────────
  static Future<void> check() async {
    state = UpdState.checking;
    message = '';
    _log('check: started');
    _notify();
    try {
      final pkgInfo = await PackageInfo.fromPlatform();
      final packageBuild = int.tryParse(pkgInfo.buildNumber) ?? 0;
      final currentBuild =
          packageBuild > _installedBuild ? packageBuild : _installedBuild;
      _log('check: currentBuild=$currentBuild packageBuild=$packageBuild');

      // Use the public releases/latest page redirect instead of the API
      // endpoint — the API has a 60 req/hour anonymous rate limit that
      // carrier NAT quickly exhausts; the web redirect has no such limit.
      // GET /releases/latest → 302 → /releases/tag/build-N  (or 404 if none)
      final releaseClient = http.Client();
      String tagName;
      try {
        final req = http.Request('GET', Uri.parse(_releasesLatest))
          ..followRedirects = false;
        final streamed = await releaseClient
            .send(req)
            .timeout(const Duration(seconds: 10));
        _log('check: releases/latest status=${streamed.statusCode}');

        if (streamed.statusCode == 404) {
          state = UpdState.upToDate;
          message = 'Build $currentBuild — no releases yet';
          _notify();
          return;
        }
        if (streamed.statusCode != 302 && streamed.statusCode != 301) {
          throw Exception('releases/latest returned ${streamed.statusCode}');
        }
        final location = streamed.headers['location'] ?? '';
        _log('check: location=$location');
        // location ends with /releases/tag/build-N
        tagName = Uri.parse(location).pathSegments.last;
      } finally {
        releaseClient.close();
      }

      final latestBuild =
          int.tryParse(tagName.replaceFirst('build-', '')) ?? 0;
      _log('check: latestBuild=$latestBuild tag=$tagName');

      if (latestBuild <= currentBuild) {
        state = UpdState.upToDate;
        message = 'Build $currentBuild';
        _notify();
        return;
      }

      final downloadUrl =
          '$_repoBase/releases/download/$tagName/hex-canvas.apk';
      _log('check: downloadUrl=$downloadUrl');

      state = UpdState.available;
      updateInfo = UpdateInfo(
        latestBuild: latestBuild,
        downloadUrl: downloadUrl,
        releaseName: 'Build $latestBuild',
      );
      message = updateInfo!.releaseName;
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
      _log('check: ERROR — $e');
    }
    _notify();
  }

  static Future<void> download() async {
    if (updateInfo == null) return;
    state = UpdState.downloading;
    progress = 0;
    _log('download: starting url=${updateInfo!.downloadUrl}');
    _notify();

    final client = http.Client();
    try {
      // Resolve destination path (same dir as native apkFile())
      final dir = await getExternalStorageDirectory();
      if (dir == null) throw Exception('External storage unavailable');
      final apk = File('${dir.path}/hex_canvas_update.apk');
      _log('download: dest=${apk.path}');

      // Remove stale file so we always write fresh bytes
      if (apk.existsSync()) {
        apk.deleteSync();
        _log('download: deleted existing APK');
      }

      final request = http.Request('GET', Uri.parse(updateInfo!.downloadUrl))
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36';
      // followRedirects defaults to true; maxRedirects defaults to 5

      final streamed = await client.send(request);
      _log('download: HTTP ${streamed.statusCode}'
          ' contentLength=${streamed.contentLength}');

      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}');
      }

      final contentLength = streamed.contentLength ?? 0;
      final sink = apk.openWrite();
      int received = 0;

      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          progress = received / contentLength;
          _notify();
        }
      }
      await sink.flush();
      await sink.close();
      _log('download: wrote ${received}B to disk');

      // Sanity-check: valid APK (ZIP) starts with PK\x03\x04 = 50 4b 03 04
      try {
        final header =
            await apk.openRead(0, 4).expand((x) => x).toList();
        final magic =
            header.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        _log('download: magic=$magic'
            ' (valid APK = "50 4b 03 04")');
        if (header.length >= 2 && header[0] == 0x50 && header[1] == 0x4b) {
          _log('download: APK signature OK');
        } else {
          _log('download: WARNING — not a ZIP/APK! first bytes=$magic');
        }
      } catch (e) {
        _log('download: could not read magic bytes — $e');
      }

      downloadedFile = apk;
      state = UpdState.ready;
      _notify();
      await checkInstallReady();
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
      _log('download: ERROR — $e');
      _notify();
    } finally {
      client.close();
    }
  }

  static Future<void> install() async {
    _log('install: called, downloadedFile=${downloadedFile?.path}');
    if (downloadedFile == null) {
      _log('install: ABORT — downloadedFile is null');
      return;
    }
    try {
      _log('install: calling native installApk path=${downloadedFile!.path}');
      await _channel
          .invokeMethod<void>('installApk', {'path': downloadedFile!.path});
      _log('install: native returned success — installer launched');
      message = 'Установщик запущен — следуйте его инструкциям';
    } on PlatformException catch (e) {
      _log('install: PlatformException code=${e.code} message=${e.message}');
      if (e.code == 'NEED_PERMISSION') {
        message = e.message ??
            'Разрешите установку из неизвестных источников, затем нажмите Install снова.';
      } else {
        state = UpdState.error;
        message = e.message ?? e.toString();
      }
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
      _log('install: ERROR — $e');
    }
    _notify();
  }
}
