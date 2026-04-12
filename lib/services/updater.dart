import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

// ── Updater singleton ──────────────────────────────────────────────────────
// All state is static so it survives bottom-sheet close/reopen.
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

  static final List<VoidCallback> _listeners = [];
  static void addListener(VoidCallback fn) => _listeners.add(fn);
  static void removeListener(VoidCallback fn) => _listeners.remove(fn);
  static void _notify() {
    for (final fn in List.of(_listeners)) fn();
  }

  // ── Public actions ────────────────────────────────────────────────────────
  static Future<void> check() async {
    state = UpdState.checking;
    message = '';
    _notify();
    try {
      final pkgInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(pkgInfo.buildNumber) ?? 0;

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
      if (assets.isEmpty) {
        throw Exception('Release has no APK asset');
      }
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
    _notify();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/hex_canvas_update.apk');

      final request = http.Request('GET', Uri.parse(updateInfo!.downloadUrl));
      final response =
          await request.send().timeout(const Duration(minutes: 5));

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          progress = received / total;
          _notify();
        }
      }).asFuture<void>();

      await sink.close();
      downloadedFile = file;
      state = UpdState.ready;
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
    }
    _notify();
  }

  static Future<void> install() async {
    if (downloadedFile == null) return;
    try {
      await _channel
          .invokeMethod<void>('installApk', {'path': downloadedFile!.path});
    } catch (e) {
      state = UpdState.error;
      message = e.toString();
      _notify();
    }
  }
}
