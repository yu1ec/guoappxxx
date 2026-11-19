import 'package:duanju_app/app_update.dart';
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
}