import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'settings.dart';

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
  // Substrate uses tag prefix `sub-build-N` and queries the list of releases
  // via GitHub API to filter by that prefix — `releases/latest` is owned by
  // the other branch's tag scheme and cannot be reused here.
  static const _apiReleases =
      'https://api.github.com/repos/iamweasel89/musical-succotash/releases?per_page=100';
  static const _repoBase =
      'https://github.com/iamweasel89/musical-succotash';
  static const _tagPrefix = 'sub-build-';
  static const _apkAsset = 'substrate.apk';
  static const _channel = MethodChannel('substrate/updater');

  // DownloadManager constants (mirror android.app.DownloadManager)
  static const int _dmStatusSuccessful = 8;
  static const int _dmStatusFailed = 16;

  // ── Persistent state ──────────────────────────────────────────────────────
  static UpdState state = UpdState.idle;
  static String message = '';
  static double progress = 0;
  static UpdateInfo? updateInfo;
  static File? downloadedFile;
  static InstallReadiness? installReadiness;
  static int currentBuild = 0;
  static int _installedBuild = 0;

  static int? _downloadId;
  static bool _polling = false;
  static String? _systemUri;

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
    _systemUri = null;
    _notify();
  }

  /// Called when the settings sheet reopens to resume any in-progress download.
  static void resumePollingIfNeeded() {
    if (state == UpdState.downloading && _downloadId != null && !_polling) {
      _log('resumePollingIfNeeded: resuming poll for id=$_downloadId');
      _pollDownload(_downloadId!);
    }
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
      AppUpdater.currentBuild = currentBuild;
      _log('check: currentBuild=$currentBuild packageBuild=$packageBuild');

      // Query GitHub API for recent releases and find the highest sub-build-N
      // tag. Authenticated requests get 5000/hour vs 60/hour anonymous.
      final githubToken = await Settings.getGithubToken();
      final headers = githubToken.isNotEmpty
          ? {'Authorization': 'token $githubToken'}
          : const <String, String>{};
      final resp = await http
          .get(Uri.parse(_apiReleases), headers: headers)
          .timeout(const Duration(seconds: 10));
      _log('check: api status=${resp.statusCode}');
      if (resp.statusCode != 200) {
        throw Exception('api/releases returned ${resp.statusCode}');
      }
      final List<dynamic> list = jsonDecode(resp.body) as List<dynamic>;
      int latestBuild = 0;
      String tagName = '';
      for (final r in list) {
        final tag = (r as Map<String, dynamic>)['tag_name'] as String? ?? '';
        if (!tag.startsWith(_tagPrefix)) continue;
        final n = int.tryParse(tag.substring(_tagPrefix.length)) ?? 0;
        if (n > latestBuild) {
          latestBuild = n;
          tagName = tag;
        }
      }
      if (latestBuild == 0) {
        state = UpdState.upToDate;
        message = 'Build $currentBuild — no substrate releases yet';
        _notify();
        return;
      }
      _log('check: latestBuild=$latestBuild tag=$tagName');

      if (latestBuild <= currentBuild) {
        state = UpdState.upToDate;
        message = 'Build $currentBuild';
        _notify();
        return;
      }

      final downloadUrl =
          '$_repoBase/releases/download/$tagName/$_apkAsset';
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
    _systemUri = null;
    _downloadId = null;
    _log('download: starting url=${updateInfo!.downloadUrl}');
    _notify();

    try {
      final id = await _channel.invokeMethod<dynamic>(
          'startDownload', {'url': updateInfo!.downloadUrl});
      _downloadId = (id as num?)?.toInt();
      if (_downloadId == null) {
        throw Exception('startDownload returned null id');
      }
      _log('download: DownloadManager enqueued id=$_downloadId');
      _pollDownload(_downloadId!);
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
      _log('download: ERROR starting — $e');
      _notify();
    }
  }

  static Future<void> _pollDownload(int id) async {
    _polling = true;
    try {
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (state != UpdState.downloading) break;

        Map raw;
        try {
          final result =
              await _channel.invokeMethod<Map>('getDownloadStatus', {'id': id});
          if (result == null) {
            _log('poll: getDownloadStatus returned null');
            break;
          }
          raw = result;
        } catch (e) {
          _log('poll: ERROR — $e');
          state = UpdState.error;
          message = e.toString();
          _notify();
          break;
        }

        final status = (raw['status'] as num?)?.toInt() ?? 0;
        final total = (raw['total'] as num?)?.toInt() ?? 0;
        final downloaded = (raw['downloaded'] as num?)?.toInt() ?? 0;
        final sysUri = raw['systemUri'] as String? ?? '';

        _log('poll: status=$status downloaded=$downloaded total=$total');

        if (total > 0) {
          progress = downloaded / total;
          _notify();
        }

        if (status == _dmStatusSuccessful) {
          _systemUri = sysUri;
          _log('poll: SUCCESS systemUri=$_systemUri');
          downloadedFile = null; // file is owned by DownloadManager
          state = UpdState.ready;
          _notify();
          await checkInstallReady();
          break;
        } else if (status == _dmStatusFailed) {
          _log('poll: FAILED status=$status');
          state = UpdState.error;
          message = 'Download failed (status $status)';
          _notify();
          break;
        }
      }
    } finally {
      _polling = false;
    }
  }

  static Future<void> install() async {
    _log('install: called, downloadId=$_downloadId');
    if (_downloadId == null) {
      _log('install: ABORT — _downloadId is null');
      return;
    }
    try {
      _log('install: calling native installApk id=$_downloadId');
      final uri = await _channel
          .invokeMethod<String>('installApk', {'id': _downloadId});
      _log('install: native returned success uri=$uri — installer launched');
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
