import 'package:duanju_app/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseReleaseTag maps app-v tag to pubspec style', () {
    expect(parseReleaseTag('app-v0.3.1-90'), '0.3.1+90');
    expect(parseReleaseTag('v1.2.3-4'), '1.2.3+4');
    expect(parseReleaseTag('0.2.0'), '0.2.0');
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