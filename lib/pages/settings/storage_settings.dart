import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/services/storage/image_cache_service.dart';
import 'package:kazumi/services/player/player_video_cache_service.dart';

class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  final _cache = ImageCacheService();
  late Future<int> _cacheSize = _cache.sizeInBytes();
  bool _clearing = false;
  bool _clearingVideo = false;
  late Future<int> _videoCacheSize = PlayerVideoCacheService.size();

  Future<void> _clearVideoCache() async {
    if (_clearingVideo) return;
    final confirmed = await KazumiDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.video_file_outlined),
        title: const Text('清除视频缓存？'),
        content: const Text('仅删除随播播放器的临时缓存，不会删除视频下载、播放记录或设置。正在播放时不可清理。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清除缓存')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearingVideo = true);
    try {
      final cleared = await PlayerVideoCacheService.clearIfIdle();
      if (mounted) {
        _message(cleared ? '视频临时缓存已清除' : '播放器正在使用缓存，请退出播放页后再清除');
      }
    } catch (_) {
      if (mounted) _message('视频缓存清理失败');
    } finally {
      if (mounted) {
        setState(() {
          _clearingVideo = false;
          _videoCacheSize = PlayerVideoCacheService.size();
        });
      }
    }
  }

  void _refreshSize() => setState(() => _cacheSize = _cache.sizeInBytes());

  void _message(String message) {
    KazumiDialog.showToast(context: context, message: message);
  }

  Future<void> _confirmClear() async {
    if (_clearing) return;
    final confirmed = await KazumiDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cleaning_services_rounded),
        title: const Text('清除图片缓存？'),
        content: const Text('图片会在下次加载时重新下载。视频、记录和设置不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除缓存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _cache.clear();
      if (!mounted) return;
      _message('图片缓存已清除');
      _refreshSize();
    } catch (_) {
      if (mounted) _message('清除失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  String _cacheDescription(AsyncSnapshot<int> snapshot) {
    if (_clearing) return '正在清除…';
    if (snapshot.connectionState != ConnectionState.done) return '正在统计…';
    if (snapshot.hasError) return '统计失败';
    return '${(snapshot.requireData / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('存储与日志'),
        body: FutureBuilder<int>(
          future: _cacheSize,
          builder: (context, snapshot) => SettingsList(
            sections: [
              SettingsSection(
                title: const Text('缓存'),
                tiles: [
                  SettingsTile(
                    leading: Icons.image_outlined,
                    title: const Text('清除图片缓存'),
                    description: Text(_cacheDescription(snapshot)),
                    enabled: snapshot.connectionState == ConnectionState.done &&
                        !_clearing,
                    onPressed: (_) => _confirmClear(),
                    trailing:
                        snapshot.connectionState == ConnectionState.done &&
                                snapshot.hasError &&
                                !_clearing
                            ? IconButton(
                                tooltip: '重新统计',
                                onPressed: _refreshSize,
                                icon: const Icon(Icons.refresh_rounded),
                              )
                            : const Icon(Icons.cleaning_services_rounded),
                  ),
                  SettingsTile(
                    leading: Icons.video_file_outlined,
                    title: const Text('清除视频缓存'),
                    description: FutureBuilder<int>(
                      future: _videoCacheSize,
                      builder: (_, snapshot) => Text(_clearingVideo
                          ? '正在清理…'
                          : snapshot.hasData
                              ? '${(snapshot.data! / (1024 * 1024)).toStringAsFixed(2)} MB'
                              : '正在统计…'),
                    ),
                    enabled: !_clearingVideo,
                    onPressed: (_) => _clearVideoCache(),
                  ),
                ],
              ),
              SettingsSection(
                title: const Text('诊断'),
                tiles: [
                  SettingsTile(
                    leading: Icons.receipt_long_rounded,
                    title: const Text('错误日志'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onPressed: (_) =>
                        context.pushNamed('/settings/storage/logs'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
