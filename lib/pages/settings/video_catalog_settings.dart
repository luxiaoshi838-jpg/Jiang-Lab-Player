import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/services/storage/storage.dart';

/// The credential is provided by the user, never compiled into public code.
class VideoCatalogSettingsPage extends StatefulWidget {
  const VideoCatalogSettingsPage({super.key});

  @override
  State<VideoCatalogSettingsPage> createState() =>
      _VideoCatalogSettingsPageState();
}

class _VideoCatalogSettingsPageState extends State<VideoCatalogSettingsPage> {
  late final TextEditingController _token;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(
      text: GStorage.getSetting(SettingsKeys.tmdbReadAccessToken),
    );
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final raw = _token.text.trim().replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
      await GStorage.putSetting(SettingsKeys.tmdbReadAccessToken, raw);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(raw.isEmpty
              ? '已停用 TMDB 搜索，Bangumi 和播放规则不受影响'
              : '已保存 TMDB 凭据；返回搜索页即可检索影视节目'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('影视资料库'),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TMDB（The Movie Database）',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('TMDB 为电影、电视剧、综艺、纪录片提供作品资料，'
              '不是视频播放线路。留空时仍使用 Bangumi、原有来源规则和百科目录。'),
          const SizedBox(height: 20),
          TextField(
            controller: _token,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'TMDB API Read Access Token（只读）',
              hintText: '在 TMDB 账户的 API 页面申请',
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示凭据' : '隐藏凭据',
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('凭据只存于本机应用设置，不上传 GitHub。'
              '本地设置未经过系统密钥库加密，请勿粘贴账户密码。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存设置'),
          ),
          const SizedBox(height: 24),
          const Text('资料由 TMDB 提供。This product uses the TMDB API '
              'but is not endorsed or certified by TMDB.'),
          const SizedBox(height: 8),
          const SelectableText('https://www.themoviedb.org'),
        ],
      ),
    ),
  );
}
