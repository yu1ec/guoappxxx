import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_build.dart';
import 'app_layout.dart';

const githubOwner = 'yu1ec';
const githubRepo = 'guoappxxx';
const updateUserAgent = 'duanju-app';

/// 与 mole-desktop 相同的 GitHub 加速前缀。
const mirrorPrefixes = [
  'https://ghfast.top/',
  'https://gh-proxy.com/',
  'https://mirror.ghproxy.com/',
];

const _latestReleaseApi =
    'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

const checkTimeout = Duration(seconds: 25);
const downloadTimeout = Duration(minutes: 10);

class AppUpdateCheck {
  const AppUpdateCheck({
    required this.currentVersion,
    required this.updateAvailable,
    required this.releaseUrl,
    this.latestVersion,
    this.assetName,
    this.downloadUrl,
    this.assetSize,
    this.error,
  });

  final String currentVersion;
  final String? latestVersion;
  final bool updateAvailable;
  final String releaseUrl;
  final String? assetName;
  final String? downloadUrl;
  final int? assetSize;
  final String? error;
}

/// 将 GitHub tag `app-v0.3.1-90` 转为 pubspec 全号 `0.3.1+90`。
String parseReleaseTag(String tag) {
  var value = tag.trim();
  if (value.startsWith('app-v')) {
    value = value.substring(5);
  } else if (value.startsWith('v')) {
    value = value.substring(1);
  }
  final dash = value.lastIndexOf('-');
  if (dash > 0) {
    final tail = value.substring(dash + 1);
    if (RegExp(r'^\d+$').hasMatch(tail)) {
      return '${value.substring(0, dash)}+$tail';
    }
  }
  return value;
}

class _ParsedVersion {
  const _ParsedVersion(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final int build;
}

_ParsedVersion parseAppVersion(String raw) {
  var value = raw.trim();
  if (value.startsWith('v')) value = value.substring(1);
  final plus = value.indexOf('+');
  final build = plus >= 0 ? int.tryParse(value.substring(plus + 1)) ?? 0 : 0;
  final semver = plus >= 0 ? value.substring(0, plus) : value;
  final parts = semver.split('.');
  int part(int index) =>
      index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0;
  return _ParsedVersion(part(0), part(1), part(2), build);
}

/// 负数表示 [a] 更旧，0 相等，正数 [a] 更新。
int compareAppVersions(String a, String b) {
  final left = parseAppVersion(a);
  final right = parseAppVersion(b);
  for (final pair in [
    (left.major, right.major),
    (left.minor, right.minor),
    (left.patch, right.patch),
    (left.build, right.build),
  ]) {
    if (pair.$1 != pair.$2) return pair.$1.compareTo(pair.$2);
  }
  return 0;
}

bool isUpdateAvailable(String current, String latest) =>
    compareAppVersions(current, latest) < 0;

/// 远端 latest 与当前一致且 APK 资产可下载时，允许同版本覆盖重装。
bool canRedownloadSameVersion(AppUpdateCheck check) {
  if (check.error != null) return false;
  final latest = check.latestVersion;
  if (latest == null) return false;
  if (check.downloadUrl == null || check.assetName == null) return false;
  return compareAppVersions(check.currentVersion, latest) == 0;
}

/// Flutter `--split-per-abi` 在 [versionCode] 上加 ABI 段（arm64 2xxx、v7 1xxx、x86_64 4xxx）。
String normalizeAppVersionForCompare(String raw) {
  final parsed = parseAppVersion(raw);
  if (parsed.build < 1000) return raw.trim();
  return '${parsed.major}.${parsed.minor}.${parsed.patch}+${parsed.build % 1000}';
}

List<String> candidateCheckUrls(bool accelerate) {
  final urls = <String>[_latestReleaseApi];
  if (accelerate) {
    urls.addAll(mirrorPrefixes.map((prefix) => '$prefix$_latestReleaseApi'));
  }
  return urls;
}

List<String> candidateDownloadUrls(String githubUrl, bool accelerate) {
  if (!accelerate) return [githubUrl];
  return [
    ...mirrorPrefixes.map((prefix) => '$prefix$githubUrl'),
    githubUrl,
  ];
}

String? matchApkAssetName({
  required Iterable<Map<String, dynamic>> assets,
  required String slug,
  required String abi,
}) {
  final pattern = RegExp('^${RegExp.escape(slug)}-.+-${RegExp.escape(abi)}\\.apk\$');
  for (final asset in assets) {
    final name = asset['name'];
    if (name is String && pattern.hasMatch(name)) return name;
  }
  return null;
}

String? assetDownloadUrl(
  Iterable<Map<String, dynamic>> assets,
  String assetName,
) {
  for (final asset in assets) {
    if (asset['name'] == assetName) {
      final url = asset['browser_download_url'];
      if (url is String && url.isNotEmpty) return url;
    }
  }
  return null;
}

int? assetSizeOf(
  Iterable<Map<String, dynamic>> assets,
  String assetName,
) {
  for (final asset in assets) {
    if (asset['name'] != assetName) continue;
    final size = asset['size'];
    if (size is int && size > 0) return size;
    if (size is num && size > 0) return size.round();
  }
  return null;
}

String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 有总大小时返回 0–1，否则返回 null（交给进度条做不确定动画）。
double? appUpdateProgressValue(int downloaded, int? total) {
  if (total == null || total <= 0) return null;
  return (downloaded / total).clamp(0.0, 1.0);
}

String appUpdateProgressLabel({
  required int downloaded,
  int? total,
  bool installing = false,
}) {
  if (installing) return '正在安装…';
  if (downloaded <= 0) return '正在连接下载…';
  if (total != null && total > 0) {
    final percent = ((downloaded / total) * 100).clamp(0, 100).floor();
    return '正在下载 $percent%（${formatByteSize(downloaded)} / ${formatByteSize(total)}）';
  }
  return '正在下载 ${formatByteSize(downloaded)}';
}

Future<Map<String, dynamic>> _fetchJson(List<String> urls) async {
  final client = HttpClient()..userAgent = updateUserAgent;
  Object? lastError;
  try {
    for (final url in urls) {
      try {
        final request = await client.getUrl(Uri.parse(url)).timeout(checkTimeout);
        request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
        final response = await request.close().timeout(checkTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
        }
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(checkTimeout);
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (error) {
        lastError = error;
      }
    }
  } finally {
    client.close(force: true);
  }
  throw lastError ?? const HttpException('无法检查更新');
}

Future<AppUpdateCheck> checkForAppUpdate({
  required String currentVersion,
  required String apkAbi,
  required bool accelerate,
}) async {
  currentVersion = normalizeAppVersionForCompare(currentVersion);
  if (!Platform.isAndroid) {
    return AppUpdateCheck(
      currentVersion: currentVersion,
      updateAvailable: false,
      releaseUrl:
          'https://github.com/$githubOwner/$githubRepo/releases/latest',
      error: '仅 Android 支持应用内更新',
    );
  }
  try {
    final release = await _fetchJson(candidateCheckUrls(accelerate));
    final tag = release['tag_name'] as String? ?? '';
    final latest = parseReleaseTag(tag);
    final releaseUrl = release['html_url'] as String? ??
        'https://github.com/$githubOwner/$githubRepo/releases/latest';
    final assets = (release['assets'] as List?)
            ?.whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList() ??
        const <Map<String, dynamic>>[];
    final assetName = matchApkAssetName(
      assets: assets,
      slug: appSlug,
      abi: apkAbi,
    );
    final downloadUrl =
        assetName == null ? null : assetDownloadUrl(assets, assetName);
    final assetSize =
        assetName == null ? null : assetSizeOf(assets, assetName);
    final newer = isUpdateAvailable(currentVersion, latest);
    final canInstall = assetName != null && downloadUrl != null;
    return AppUpdateCheck(
      currentVersion: currentVersion,
      latestVersion: latest,
      updateAvailable: newer && canInstall,
      releaseUrl: releaseUrl,
      assetName: assetName,
      downloadUrl: downloadUrl,
      assetSize: assetSize,
    );
  } catch (error) {
    return AppUpdateCheck(
      currentVersion: currentVersion,
      updateAvailable: false,
      releaseUrl:
          'https://github.com/$githubOwner/$githubRepo/releases/latest',
      error: error.toString(),
    );
  }
}

typedef UpdateDownloadProgress = void Function(int downloaded, int? total);

Future<String> downloadAppUpdate({
  required String downloadUrl,
  required String assetName,
  required bool accelerate,
  int? expectedSize,
  UpdateDownloadProgress? onProgress,
}) async {
  final client = HttpClient()..userAgent = updateUserAgent;
  Object? lastError;
  try {
    for (final url in candidateDownloadUrls(downloadUrl, accelerate)) {
      try {
        final request =
            await client.getUrl(Uri.parse(url)).timeout(downloadTimeout);
        final response = await request.close().timeout(downloadTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
        }
        final dir = await _updateCacheDir();
        final target = File(p.join(dir.path, assetName));
        if (target.existsSync()) await target.delete();
        final sink = target.openWrite();
        var downloaded = 0;
        final headerTotal =
            response.contentLength >= 0 ? response.contentLength : null;
        final total = headerTotal ?? expectedSize;
        onProgress?.call(0, total);
        await for (final chunk in response.timeout(downloadTimeout)) {
          sink.add(chunk);
          downloaded += chunk.length;
          onProgress?.call(downloaded, total);
        }
        await sink.flush();
        await sink.close();
        return target.path;
      } catch (error) {
        lastError = error;
      }
    }
  } finally {
    client.close(force: true);
  }
  throw lastError ?? const HttpException('下载失败');
}

Future<Directory> _updateCacheDir() async {
  final cache = await getTemporaryDirectory();
  final dir = Directory(p.join(cache.path, 'app_updates'));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

Future<void> installDownloadedApk(String path) async {
  if (!Platform.isAndroid) return;
  await AppDevice.channel.invokeMethod('installApk', {'path': path});
}

Future<void> openReleasePage(String url) async {
  if (!Platform.isAndroid) {
    if (kIsWeb) return;
    throw UnsupportedError('仅 Android 支持打开下载页');
  }
  await AppDevice.channel.invokeMethod('openUrl', {'url': url});
}