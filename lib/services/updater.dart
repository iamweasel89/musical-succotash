import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

// ── Update state ───────────────────────────────────────────────────────────
enum UpdState { idle, checking, upToDate, available, downloading, ready, error }

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

// DownloadManager status codes (mirrors Android constants)
const _dmSuccessful = 8;
const _dmFailed = 16;

// ── Updater singleton ──────────────────────────────────────────────────────
// All state is static — survives bottom-sheet close/reopen/backgrounding.
// Download runs via Android DownloadManager (native), so backgrounding
// does not interrupt it.
class AppUpdater {
  static const _apiUrl =
      'https://api.github.com/repos/iamweasel89/musical-succotash/releases/latest';
  static const _channel = MethodChannel('hex_canvas/updater');

  // ── Persistent state ──────────────────────────────────────────────────────
  static UpdState state = UpdState.idle;
  static String message = '';
  static double progress = 0;
  static UpdateInfo? updateInfo;
  static File? downloadedFile;
  static int? _downloadId;
  static bool _polling = false;
  static int _installedBuild = 0; // set when install is triggered

  static final List<void Function()> _listeners = [];
  static void addListener(void Function() fn) => _listeners.add(fn);
  static void removeListener(void Function() fn) => _listeners.remove(fn);
  static void _notify() {
    for (final fn in List.of(_listeners)) fn();
  }

  /// Call when the update UI becomes visible (e.g. sheet reopened after
  /// coming back from background) to resume progress polling.
  static void resumePollingIfNeeded() {
    if (state == UpdState.downloading && _downloadId != null && !_polling) {
      _pollDownload();
    }
  }

  // ── Public actions ────────────────────────────────────────────────────────
  static Future<void> check() async {
    state = UpdState.checking;
    message = '';
    _notify();
    try {
      final pkgInfo = await PackageInfo.fromPlatform();
      final packageBuild = int.tryParse(pkgInfo.buildNumber) ?? 0;
      // Use the higher of the two: actual installed build (after restart)
      // or the build we last triggered an install for (same session).
      final currentBuild =
          packageBuild > _installedBuild ? packageBuild : _installedBuild;

      final resp = await http
          .get(Uri.parse(_apiUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 404) {
        state = UpdState.upToDate;
        message = 'Build $currentBuild — no releases yet';
        _notify();
        return;
      }
      if (resp.statusCode != 200) {
        throw Exception('GitHub API returned ${resp.statusCode}');
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = json['tag_name'] as String? ?? '';
      final latestBuild =
          int.tryParse(tagName.replaceFirst('build-', '')) ?? 0;

      if (latestBuild <= currentBuild) {
        state = UpdState.upToDate;
        message = 'Build $currentBuild';
        _notify();
        return;
      }

      final assets = json['assets'] as List<dynamic>;
      if (assets.isEmpty) throw Exception('Release has no APK asset');
      final downloadUrl = (assets.first as Map<String, dynamic>)
          ['browser_download_url'] as String;

      state = UpdState.available;
      updateInfo = UpdateInfo(
        latestBuild: latestBuild,
        downloadUrl: downloadUrl,
        releaseName: json['name'] as String? ?? 'Build $latestBuild',
      );
      message = updateInfo!.releaseName;
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
    }
    _notify();
  }

  static Future<void> download() async {
    if (updateInfo == null) return;
    state = UpdState.downloading;
    progress = 0;
    _downloadId = null;
    _notify();
    try {
      final id = await _channel.invokeMethod<int>(
        'startDownload',
        {'url': updateInfo!.downloadUrl},
      );
      _downloadId = id;
      _pollDownload();
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
      _notify();
    }
  }

  static Future<void> install() async {
    if (downloadedFile == null) return;
    try {
      await _channel
          .invokeMethod<void>('installApk', {'path': downloadedFile!.path});
      // Remember what we installed so check() doesn't offer it again
      // before the app fully restarts with the new build number.
      _installedBuild = updateInfo?.latestBuild ?? _installedBuild;
      state = UpdState.idle;
      downloadedFile = null;
      _downloadId = null;
    } on PlatformException catch (e) {
      if (e.code == 'NEED_PERMISSION') {
        // The Settings page was opened so the user can grant permission.
        // Keep state = ready so the Install button stays visible for retry.
        message = e.message ??
            'Enable "Install unknown apps" for Hex Canvas in Settings, then tap Install again.';
        // state stays UpdState.ready
      } else {
        state = UpdState.error;
        message = e.message ?? e.toString();
      }
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
    }
    _notify();
  }

  // ── Internal polling loop ─────────────────────────────────────────────────
  static Future<void> _pollDownload() async {
    if (_polling) return;
    _polling = true;
    try {
      while (state == UpdState.downloading && _downloadId != null) {
        await Future.delayed(const Duration(milliseconds: 700));

        final raw = await _channel.invokeMethod<Map>(
          'getDownloadStatus',
          {'id': _downloadId},
        );
        if (raw == null) break;

        final dmStatus = (raw['status'] as num).toInt();
        final total = (raw['total'] as num).toInt();
        final downloaded = (raw['downloaded'] as num).toInt();
        final filePath = raw['filePath'] as String? ?? '';

        if (dmStatus == _dmSuccessful) {
          if (filePath.isNotEmpty) {
            downloadedFile = File(filePath);
            state = UpdState.ready;
          } else {
            state = UpdState.error;
            message = 'Download complete but file path is empty';
          }
          break;
        } else if (dmStatus == _dmFailed) {
          state = UpdState.error;
          message = 'Download failed (DownloadManager error)';
          break;
        } else {
          // pending / running / paused — update progress
          if (total > 0) progress = downloaded / total;
        }
        _notify();
      }
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
    }
    _polling = false;
    _notify();
  }
}
