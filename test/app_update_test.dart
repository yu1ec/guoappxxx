import 'package:duanju_app/app_update.dart';
import 'package:duanju_app/update_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseReleaseTag maps app-v tag to pubspec style', () {
    expect(parseReleaseTag('app-v0.3.1-90'), '0.3.1+90');
    expect(parseReleaseTag('v1.2.3-4'), '1.2.3+4');
    expect(parseReleaseTag('0.2.0'), '0.2.0');
  });

  test('normalizeAppVersionForCompare undoes split-per-abi versionCode', () {
    expect(normalizeAppVersionForCompare('0.3.1+2090'), '0.3.1+90');
    expect(normalizeAppVersionForCompare('0.3.1+1090'), '0.3.1+90');
    expect(normalizeAppVersionForCompare('0.3.1+90'), '0.3.1+90');
    expect(isUpdateAvailable('0.3.1+2090', '0.3.1+91'), isTrue);
    expect(isUpdateAvailable('0.3.1+2090', '0.3.1+90'), isFalse);
  });

  test('canRedownloadSameVersion when same version and asset present', () {
    const same = AppUpdateCheck(
      currentVersion: '0.3.1+90',
      latestVersion: '0.3.1+90',
      updateAvailable: false,
      releaseUrl: 'https://example.com',
      assetName: 'quanjushijie-0.3.1+90-arm64-v8a.apk',
      downloadUrl: 'https://example.com/foo.apk',
    );
    expect(canRedownloadSameVersion(same), isTrue);

    const newer = AppUpdateCheck(
      currentVersion: '0.3.1+89',
      latestVersion: '0.3.1+90',
      updateAvailable: true,
      releaseUrl: 'https://example.com',
      assetName: 'foo.apk',
      downloadUrl: 'https://example.com/foo.apk',
    );
    expect(canRedownloadSameVersion(newer), isFalse);

    const noUrl = AppUpdateCheck(
      currentVersion: '0.3.1+90',
      latestVersion: '0.3.1+90',
      updateAvailable: false,
      releaseUrl: 'https://example.com',
    );
    expect(canRedownloadSameVersion(noUrl), isFalse);

    const withError = AppUpdateCheck(
      currentVersion: '0.3.1+90',
      updateAvailable: false,
      releaseUrl: 'https://example.com',
      error: '网络错误',
    );
    expect(canRedownloadSameVersion(withError), isFalse);
  });

  test('compareAppVersions semver then build', () {
    expect(compareAppVersions('0.3.0+10', '0.3.1+1'), lessThan(0));
    expect(compareAppVersions('0.3.1+89', '0.3.1+90'), lessThan(0));
    expect(compareAppVersions('0.3.1+90', '0.3.1+90'), 0);
    expect(isUpdateAvailable('0.3.1+89', '0.3.1+90'), isTrue);
    expect(isUpdateAvailable('0.3.1+90', '0.3.1+90'), isFalse);
  });

  test('candidateCheckUrls prefers direct GitHub API', () {
    final urls = candidateCheckUrls(true);
    expect(urls.first, contains('api.github.com'));
    expect(urls.length, mirrorPrefixes.length + 1);
    expect(urls[1], startsWith('https://ghfast.top/'));
  });

  test('candidateDownloadUrls mirror before github', () {
    const github =
        'https://github.com/yu1ec/guoappxxx/releases/download/app-v0.3.1-90/foo.apk';
    final urls = candidateDownloadUrls(github, true);
    expect(urls.length, mirrorPrefixes.length + 1);
    expect(urls.first, startsWith('https://ghfast.top/'));
    expect(urls.last, github);
  });

  test('assetSizeOf reads GitHub asset size', () {
    final assets = [
      {'name': 'foo.apk', 'size': 12345678},
      {'name': 'bar.apk', 'size': 0},
    ];
    expect(assetSizeOf(assets, 'foo.apk'), 12345678);
    expect(assetSizeOf(assets, 'bar.apk'), isNull);
    expect(assetSizeOf(assets, 'missing.apk'), isNull);
  });

  test('appUpdateProgressValue is determinate only with total', () {
    expect(appUpdateProgressValue(0, 100), 0);
    expect(appUpdateProgressValue(40, 100), 0.4);
    expect(appUpdateProgressValue(10, null), isNull);
    expect(appUpdateProgressValue(10, 0), isNull);
  });

  test('appUpdateProgressLabel shows download and install states', () {
    expect(
      appUpdateProgressLabel(downloaded: 0, total: 20 * 1024 * 1024),
      '正在连接下载…',
    );
    expect(
      appUpdateProgressLabel(downloaded: 10 * 1024 * 1024, total: 20 * 1024 * 1024),
      '正在下载 50%（10.0 MB / 20.0 MB）',
    );
    expect(appUpdateProgressLabel(downloaded: 1024), '正在下载 1.0 KB');
    expect(appUpdateProgressLabel(downloaded: 0), '正在连接下载…');
    expect(
      appUpdateProgressLabel(downloaded: 10, total: 20, installing: true),
      '正在安装…',
    );
  });

  test('matchApkAssetName picks slug and abi', () {
    final assets = [
      {'name': 'quanjushijie-0.3.1+90-arm64-v8a.apk'},
      {'name': 'duanjushijie-0.3.1+90-armeabi-v7a.apk'},
    ];
    expect(
      matchApkAssetName(
        assets: assets.map(Map<String, dynamic>.from),
        slug: 'quanjushijie',
        abi: 'arm64-v8a',
      ),
      'quanjushijie-0.3.1+90-arm64-v8a.apk',
    );
    expect(
      matchApkAssetName(
        assets: assets.map(Map<String, dynamic>.from),
        slug: 'quanjushijie',
        abi: 'x86_64',
      ),
      isNull,
    );
  });

  testWidgets('AppUpdateProgressBar shows determinate download progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppUpdateProgressBar(
            downloaded: 10 * 1024 * 1024,
            total: 20 * 1024 * 1024,
          ),
        ),
      ),
    );
    expect(find.text('正在下载 50%（10.0 MB / 20.0 MB）'), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
      0.5,
    );
  });

  testWidgets('AppUpdateProgressBar is indeterminate without total size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppUpdateProgressBar(downloaded: 1024),
        ),
      ),
    );
    expect(find.text('正在下载 1.0 KB'), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
      isNull,
    );
  });
}