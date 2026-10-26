import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/services/player/yt_dlp_url_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// An isolated URL-playback screen. Existing rules and danmaku are untouched.
class YtDlpUrlPage extends StatefulWidget {
  const YtDlpUrlPage({super.key});

  @override
  State<YtDlpUrlPage> createState() => _YtDlpUrlPageState();
}

class _YtDlpUrlPageState extends State<YtDlpUrlPage> {
  final _address = TextEditingController();
  final _resolver = YtDlpUrlService();
  bool _busy = false;
  String? _error;
  YtDlpResolvedVideo? _resolved;
  Player? _player;
  VideoController? _controller;

  @override
  void dispose() {
    _address.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _openUrl() async {
    if (_busy || !Platform.isWindows) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _resolver.resolve(_address.text);
      if (!mounted) return;
      final old = _player;
      if (old != null) await old.dispose();
      if (!mounted) return;
      final player = Player();
      final video = VideoController(player);
      _player = player;
      setState(() {
        _resolved = info;
        _controller = video;
      });
      await player.open(Media(info.url, httpHeaders: info.headers));
    } on YtDlpUrlException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '视频打开失败，可尝试重新解析或更换网址');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('视频网址解析'),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('输入受 yt-dlp 支持的视频页面网址，解析后在随播内播放。'),
          const SizedBox(height: 8),
          const Text('此功能不影响现有影视规则、搜索、播放线路和弹幕。'),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '视频网页地址',
              hintText: 'https://www.example.com/video/...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _openUrl(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || !Platform.isWindows ? null : _openUrl,
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_circle_outline),
            label: Text(_busy ? '正在解析…' : '解析并播放'),
          ),
          if (!Platform.isWindows) ...[
            const SizedBox(height: 12),
            const Text('Android 端尚未集成 yt-dlp 运行环境，本入口暂时只在 Windows 可用。'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_resolved != null && _controller != null) ...[
            const SizedBox(height: 20),
            Text(_resolved!.title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: _controller!),
            ),
            const SizedBox(height: 8),
            const Text('媒体地址可能过期；无法播放时重新解析。此入口不提供自动弹幕匹配。'),
          ],
        ],
      ),
    ),
  );
}
