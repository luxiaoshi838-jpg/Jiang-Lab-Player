import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

/// Searches user-installed rules, not Bangumi metadata. Does not bundle sources.
class SuiboSearchPage extends StatefulWidget {
  const SuiboSearchPage({super.key});
  @override
  State<SuiboSearchPage> createState() => _SuiboSearchPageState();
}

class _SuiboSearchPageState extends State<SuiboSearchPage> {
  final input = TextEditingController();
  final PluginsController pluginsController = inject<PluginsController>();
  final Map<String, List<SearchItem>> results = {};
  final Map<String, String> errors = {};
  String keyword = '';
  bool busy = false;
  bool opening = false;
  int generation = 0;

  @override
  void dispose() {
    generation++;
    input.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final next = input.text.trim();
    if (next.isEmpty) return;
    final mine = ++generation;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() { keyword = next; busy = true; results.clear(); errors.clear(); });
    final rules = List<Plugin>.of(pluginsController.pluginList);
    await Future.wait(rules.map((plugin) async {
      try {
        final response = await plugin.queryBangumi(next, shouldRethrow: true);
        if (mounted && mine == generation) {
          setState(() { results[plugin.name] = response.data; });
        }
      } catch (error) {
        if (mounted && mine == generation) {
          setState(() { errors[plugin.name] = error.toString(); });
        }
      }
    }));
    if (mounted && mine == generation) setState(() { busy = false; });
  }

  BangumiItem playbackIdentity(Plugin plugin, SearchItem item) {
    final identity = '${plugin.name}|${item.src}';
    final stableId = identity.codeUnits.fold<int>(
      17, (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    return BangumiItem(
      id: stableId, type: 2, name: item.name, nameCn: item.name,
      summary: '来自已安装资源规则的影视内容', airDate: '',
      airWeekday: 1, rank: 0,
      images: {'large': '', 'common': '', 'medium': '', 'small': '', 'grid': ''},
      tags: [], alias: [], ratingScore: 0.0, votes: 0, votesCount: [], info: '',
    );
  }

  Future<void> openVideo(Plugin plugin, SearchItem item) async {
    if (opening) return;
    setState(() { opening = true; });
    try {
      final roads = await plugin.queryChapterRoads(item.src);
      if (roads.isEmpty) throw StateError('没有可用播放线路');
      if (!mounted) return;
      await context.pushNamed('/video/', arguments: OnlineVideoPlaybackArgs(
        bangumiItem: playbackIdentity(plugin, item),
        plugin: plugin, title: item.name, src: item.src, roads: roads,
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开：$error')),
      );
    } finally {
      if (mounted) setState(() { opening = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = List<Plugin>.of(pluginsController.pluginList);
    final count = results.values.fold<int>(0, (sum, items) => sum + items.length);
    return Scaffold(
      appBar: AppBar(title: const Text('随播 · 影视搜索')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: TextField(
                  controller: input,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search(),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.movie_filter_outlined),
                    labelText: '电影、电视剧、综艺、纪录片和动漫',
                    hintText: '输入名称，搜索已安装的视频规则',
                  ),
                )),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: busy ? null : search,
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                ),
              ]),
            ),
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: rules.isEmpty
                ? const Center(child: Text('尚未安装规则，请先到“我的”页面安装视频规则。'))
                : keyword.isEmpty
                  ? const Center(child: Text('独立搜索影视资源，不需要先找到 Bangumi 条目。'))
                  : ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('“$keyword” · $count 条结果 · ${rules.length} 个规则'),
                      ),
                      for (final plugin in rules)
                        ExpansionTile(
                          key: PageStorageKey(plugin.name),
                          initiallyExpanded: true,
                          title: Text(plugin.name),
                          subtitle: Text(errors.containsKey(plugin.name)
                            ? '搜索失败' : results.containsKey(plugin.name)
                              ? '${results[plugin.name]!.length} 条结果' : '搜索中…'),
                          children: [
                            if (errors.containsKey(plugin.name))
                              Padding(padding: const EdgeInsets.all(12),
                                child: SelectableText(errors[plugin.name]!)),
                            for (final item in results[plugin.name] ?? <SearchItem>[])
                              ListTile(
                                title: Text(item.name),
                                leading: const Icon(Icons.play_circle_outline),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: opening ? null : () => openVideo(plugin, item),
                              ),
                          ],
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}
