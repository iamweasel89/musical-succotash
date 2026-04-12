import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

class AppUpdater {
  static const _apiUrl =
      'https://api.github.com/repos/iamweasel89/musical-succotash/releases/latest';

  /// Returns [UpdateInfo] if a newer build is available, null if already up to date.
  /// Throws on network or parse errors.
  static Future<UpdateInfo?> checkForUpdate() async {
    final pkgInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(pkgInfo.buildNumber) ?? 0;

    final resp = await http
        .get(Uri.parse(_apiUrl), headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (resp.statusCode == 404) return null; // no release published yet
    if (resp.statusCode != 200) {
      throw Exception('GitHub API returned ${resp.statusCode}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tagName = json['tag_name'] as String? ?? '';
    // tag format: "build-42"
    final latestBuild =
        int.tryParse(tagName.replaceFirst('build-', '')) ?? 0;

    if (latestBuild <= currentBuild) return null;

    final assets = json['assets'] as List<dynamic>;
    if (assets.isEmpty) return null;
    final downloadUrl = (assets.first as Map<String, dynamic>)
        ['browser_download_url'] as String;

    return UpdateInfo(
      latestBuild: latestBuild,
      downloadUrl: downloadUrl,
      releaseName: json['name'] as String? ?? 'Build $latestBuild',
    );
  }

  /// Downloads the APK to the app's temp directory.
  /// [onProgress] receives a value from 0.0 to 1.0.
  static Future<File> downloadApk(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/hex_canvas_update.apk');

    final request = http.Request('GET', Uri.parse(url));
    final response = await request.send().timeout(const Duration(minutes: 5));

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();

    await response.stream.listen((chunk) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }).asFuture<void>();

    await sink.close();
    return file;
  }

  /// Triggers the system APK installer for the given file.
  static Future<void> installApk(File file) async {
    await OpenFile.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
  }
}
