import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_layout.dart';
import 'app_update.dart';
import 'local_store.dart';
import 'widgets.dart';

class UpdateBanner extends StatefulWidget {
  const UpdateBanner({
    super.key,
    required this.store,
    required this.check,
    required this.onDismissSession,
    required this.onSkipVersion,
  });

  final LocalStore store;
  final AppUpdateCheck check;
  final VoidCallback onDismissSession;
  final VoidCallback onSkipVersion;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class AppUpdateProgressBar extends StatelessWidget {
  const AppUpdateProgressBar({
    super.key,
    required this.downloaded,
    this.total,
    this.installing = false,
  });

  final int downloaded;
  final int? total;
  final bool installing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: installing ? null : appUpdateProgressValue(downloaded, total),
        ),
        const SizedBox(height: 6),
        Text(
          appUpdateProgressLabel(
            downloaded: downloaded,
            total: total,
            installing: installing,
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _downloading = false;
  bool _installing = false;
  int _downloaded = 0;
  int? _total;
  String? _message;

  bool get _busy => _downloading || _installing;

  Future<void> _install() async {
    final url = widget.check.downloadUrl;
    final name = widget.check.assetName;
    if (url == null || name == null) return;
    setState(() {
      _downloading = true;
      _installing = false;
      _downloaded = 0;
      _total = widget.check.assetSize;
      _message = null;
    });
    try {
      final path = await downloadAppUpdate(
        downloadUrl: url,
        assetName: name,
        accelerate: widget.store.accelerateDownload,
        expectedSize: widget.check.assetSize,
        onProgress: (downloaded, total) {
          if (!mounted) return;
          setState(() {
            _downloaded = downloaded;
            _total = total ?? widget.check.assetSize;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = true;
      });
      await installDownloadedApk(path);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message ?? '安装失败');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _installing = false;
        });
      }
    }
  }

  Future<void> _openRelease() async {
    try {
      await openReleasePage(widget.check.releaseUrl);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.check.latestVersion;
    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: const Icon(Icons.system_update_rounded),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('发现新版本 ${latest ?? ''}（当前 ${widget.check.currentVersion}）'),
          if (_busy) ...[
            const SizedBox(height: 8),
            AppUpdateProgressBar(
              downloaded: _downloaded,
              total: _total,
              installing: _installing,
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: widget.onDismissSession, child: const Text('稍后')),
        TextButton(
          onPressed: _busy ? null : widget.onSkipVersion,
          child: const Text('跳过此版本'),
        ),
        if (_message != null)
          TextButton(onPressed: _openRelease, child: const Text('手动下载')),
        FilledButton(
          onPressed: _busy ? null : _install,
          child: Text(_installing ? '安装中…' : _downloading ? '下载中…' : '立即更新'),
        ),
      ],
    );
  }
}

class AppUpdateCoordinator {
  AppUpdateCoordinator({
    required this.store,
    required this.currentVersion,
    this.apkAbi,
  });

  final LocalStore store;
  final String currentVersion;
  final String? apkAbi;

  AppUpdateCheck? pending;
  bool sessionDismissed = false;
  Timer? _initialCheck;
  Timer? _interval;

  bool get shouldShowBanner {
    if (!Platform.isAndroid) return false;
    final latest = pending?.latestVersion;
    if (pending == null ||
        pending!.updateAvailable != true ||
        sessionDismissed ||
        latest == null ||
        latest == store.skippedUpdateVersion) {
      return false;
    }
    return true;
  }

  Future<AppUpdateCheck?> check({bool quiet = true}) async {
    if (!Platform.isAndroid) return null;
    final abi = apkAbi;
    if (abi == null || abi.isEmpty) return null;
    final result = await checkForAppUpdate(
      currentVersion: currentVersion,
      apkAbi: abi,
      accelerate: store.accelerateDownload,
    );
    pending = result.updateAvailable ? result : (quiet ? null : result);
    return result;
  }

  void schedulePeriodic(VoidCallback onChange) {
    _initialCheck?.cancel();
    _interval?.cancel();
    _initialCheck = Timer(const Duration(milliseconds: 1500), () async {
      await check();
      onChange();
    });
    _interval = Timer.periodic(const Duration(hours: 6), (_) async {
      await check();
      onChange();
    });
  }

  void dispose() {
    _initialCheck?.cancel();
    _interval?.cancel();
  }
}

Future<void> showAppAboutDialog(
  BuildContext context,
  LocalStore store,
) async {
  final version = AppLayout.versionOf(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('关于$appName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('版本 $version'),
          const SizedBox(height: 8),
          const Text('独立运行，打开即可浏览和播放。观看记录与追剧收藏保存在当前设备。'),
        ],
      ),
      actions: [
        if (Platform.isAndroid)
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AppUpdatePage(store: store),
                ),
              );
            },
            child: const Text('检查更新'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class AppUpdatePage extends StatelessWidget {
  const AppUpdatePage({super.key, required this.store});

  final LocalStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('检查更新')),
        body: AppUpdatePanel(store: store, compact: false),
      );
}

class AppUpdatePanel extends StatefulWidget {
  const AppUpdatePanel({
    super.key,
    required this.store,
    this.compact = true,
    this.currentVersion,
    this.apkAbi,
  });

  final LocalStore store;
  final bool compact;
  final String? currentVersion;
  final String? apkAbi;

  @override
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

class _AppUpdatePanelState extends State<AppUpdatePanel> {
  AppUpdateCheck? _result;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  int _downloaded = 0;
  int? _total;
  String? _message;

  bool get _busy => _checking || _downloading || _installing;

  String _version(BuildContext context) =>
      widget.currentVersion ?? AppLayout.versionOf(context);
  String? _abi(BuildContext context) =>
      widget.apkAbi ?? AppLayout.apkAbiOf(context);

  Future<void> _check({bool manual = false}) async {
    if (!Platform.isAndroid) {
      setState(() => _message = '仅 Android 支持应用内更新');
      return;
    }
    final abi = _abi(context);
    if (abi == null) {
      setState(() => _message = '无法读取本机安装信息');
      return;
    }
    setState(() {
      _checking = true;
      _message = null;
    });
    final result = await checkForAppUpdate(
      currentVersion: _version(context),
      apkAbi: abi,
      accelerate: widget.store.accelerateDownload,
    );
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
      if (manual && !result.updateAvailable) {
        if (result.error != null) {
          _message = result.error;
        } else if (canRedownloadSameVersion(result)) {
          _message = '当前已是最新版本，可重新下载覆盖安装';
        } else {
          _message = '当前已是最新版本';
        }
      }
    });
  }

  Future<void> _install() async {
    final check = _result;
    final url = check?.downloadUrl;
    final name = check?.assetName;
    if (check == null || url == null || name == null) return;
    setState(() {
      _downloading = true;
      _installing = false;
      _downloaded = 0;
      _total = check.assetSize;
      _message = null;
    });
    try {
      final path = await downloadAppUpdate(
        downloadUrl: url,
        assetName: name,
        accelerate: widget.store.accelerateDownload,
        expectedSize: check.assetSize,
        onProgress: (downloaded, total) {
          if (!mounted) return;
          setState(() {
            _downloaded = downloaded;
            _total = total ?? check.assetSize;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = true;
      });
      await installDownloadedApk(path);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _installing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const ListTile(
        title: Text('应用更新'),
        subtitle: Text('仅 Android 支持应用内更新'),
      );
    }
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) {
        final version = _version(context);
        final children = <Widget>[
          ListTile(
            title: const Text('应用更新'),
            subtitle: Text(
              _result?.latestVersion != null && _result!.updateAvailable
                  ? '最新版本 ${_result!.latestVersion}（当前 $version）'
                  : '当前版本 $version',
            ),
          ),
          SwitchListTile(
            value: widget.store.accelerateDownload,
            onChanged: _busy
                ? null
                : (value) => saveUserChange(
                      context,
                      () => widget.store.setAccelerateDownload(value),
                    ),
            title: const Text('国内镜像加速'),
            subtitle: const Text(
              '优先尝试 ghfast.top / gh-proxy.com 等镜像，失败后自动回退 GitHub',
            ),
          ),
          if (_checking)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  Text(
                    '正在检查更新…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (_downloading || _installing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppUpdateProgressBar(
                downloaded: _downloaded,
                total: _total,
                installing: _installing,
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_message!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _check(manual: true),
                  child: const Text('检查更新'),
                ),
                if (_result?.updateAvailable == true)
                  FilledButton(
                    onPressed: _busy ? null : _install,
                    child: Text(
                      _installing
                          ? '安装中…'
                          : _downloading
                              ? '下载中…'
                              : '更新到 ${_result!.latestVersion}',
                    ),
                  ),
                if (_result != null &&
                    !_result!.updateAvailable &&
                    canRedownloadSameVersion(_result!))
                  OutlinedButton(
                    onPressed: _busy ? null : _install,
                    child: Text(
                      _installing
                          ? '安装中…'
                          : _downloading
                              ? '下载中…'
                              : '重新下载安装',
                    ),
                  ),
              ],
            ),
          ),
        ];
        if (widget.compact) return Column(children: children);
        return ListView(children: children);
      },
    );
  }
}