import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/video_source/direct_video_source.dart';

/// One shared vertical episode picker for Android and Windows. No guessed
/// episodes or personalised recommendations: every entry comes from a rule.
class InfoEpisodeSection extends StatefulWidget {
  const InfoEpisodeSection({super.key, required this.infoController});

  final InfoController infoController;

  @override
  State<InfoEpisodeSection> createState() => InfoEpisodeSectionState();
}

class InfoEpisodeSectionState extends State<InfoEpisodeSection> {
  static const int pageSize = 50;

  final PluginsController _plugins = inject<PluginsController>();
  final HistoryController _history = inject<HistoryController>();
  BangumiItem? _boundItem;
  Plugin? _selectedPlugin;
  String _sourceTitle = '';
  String _sourceUrl = '';
  List<Road> _roads = const [];
  int _roadIndex = 0;
  int _episode = 1;
  int _page = 0;
  int _generation = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boundItem = widget.infoController.bangumiItem;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadDefault());
    });
  }

  @override
  void didUpdateWidget(covariant InfoEpisodeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_boundItem, widget.infoController.bangumiItem)) {
      _boundItem = widget.infoController.bangumiItem;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadDefault());
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  static String _normalized(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[\s·:：/\\\-_.？！!?（）()\[\]【】]'), '');

  static String keywordFrom(BangumiItem item) =>
      item.nameCn.isEmpty ? item.name : item.nameCn;

  static bool _sameWork(String candidate, BangumiItem item) {
    final value = _normalized(candidate);
    if (value.isEmpty) return false;
    return [item.nameCn, item.name, ...item.alias]
        .map(_normalized)
        .any((title) => title.isNotEmpty && title == value);
  }

  Plugin? _findPlugin(String name) {
    for (final plugin in _plugins.pluginList) {
      if (plugin.name == name && !isLiveOnlyRule(plugin.type)) {
        return plugin;
      }
    }
    return null;
  }

  bool get _ready => _selectedPlugin != null && _roads.isNotEmpty;

  void useSource(Plugin plugin, String title, String src, List<Road> roads) {
    final usable = roads.where((road) => road.data.isNotEmpty).toList();
    if (usable.isEmpty) {
      setState(() => _error = '这个来源没有可播放的集数，请尝试其他来源');
      return;
    }
    // Invalidate any still-running automatic search when the user picks a source.
    _generation++;
    final progress =
        _history.lastWatching(widget.infoController.bangumiItem, plugin.name);
    var road = progress?.road ?? 0;
    if (road < 0 || road >= usable.length) road = 0;
    var episode = progress?.episode ?? 1;
    if (episode < 1 || episode > usable[road].data.length) episode = 1;
    setState(() {
      _selectedPlugin = plugin;
      _sourceTitle = title;
      _sourceUrl = src;
      _roads = usable;
      _roadIndex = road;
      _episode = episode;
      _page = (episode - 1) ~/ pageSize;
      _loading = false;
      _error = null;
    });
  }

  Future<bool> _trySource(
      Plugin plugin, String title, String source, int generation) async {
    if (source.trim().isEmpty || generation != _generation) return false;
    try {
      final List<Road> roads;
      if (directVideoFormat(source) != null) {
        roads = [
          Road(
            name: '直接播放',
            data: [source],
            identifier: [title],
          ),
        ];
      } else {
        roads = await plugin.queryChapterRoads(source);
      }
      if (!mounted || generation != _generation) return false;
      if (!roads.any((road) => road.data.isNotEmpty)) return false;
      useSource(plugin, title, source, roads);
      return true;
    } catch (error) {
      KazumiLogger().w('InfoEpisodeSection: playlist failed for ${plugin.name}',
          error: error);
      return false;
    }
  }

  Future<void> _loadDefault() async {
    final item = widget.infoController.bangumiItem;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _selectedPlugin = null;
      _roads = const [];
    });
    final seen = <String>{};
    Future<bool> trySaved(String pluginName, String title, String url) async {
      if (!seen.add('$pluginName|$url')) return false;
      final plugin = _findPlugin(pluginName);
      if (plugin == null) return false;
      return _trySource(plugin, title, url, generation);
    }

    // Previously used source wins over installation order when still valid.
    // History retains the original rule URL without changing the Hive schema.
    final previousSources = _history.histories
        .where((history) =>
            history.bangumiItem.id == item.id &&
            history.entryKind == 'online' &&
            history.lastSrc.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    for (final history in previousSources) {
      if (!mounted || generation != _generation) return;
      if (await trySaved(history.adapterName, keywordFrom(item),
          history.lastSrc)) return;
    }

    if (item.isExternal &&
        await trySaved(item.sourcePlugin, item.nameCn, item.sourceUrl)) {
      return;
    }
    for (final hit in item.discoveredSources) {
      if (!mounted || generation != _generation) return;
      if (await trySaved(hit.pluginName, hit.title, hit.url)) return;
    }

    // For older Bangumi bookmarks there may be no saved rule identity. Search
    // the preinstalled regular rules in bounded batches and require title
    // equality; never treat metadata-only hits as playable episodes.
    final keyword = item.nameCn.trim().isEmpty ? item.name : item.nameCn;
    final eligible = _plugins.pluginList
        .where((plugin) => !isLiveOnlyRule(plugin.type))
        .toList(growable: false);
    for (var offset = 0; offset < eligible.length; offset += 4) {
      if (!mounted || generation != _generation) return;
      final batch = eligible.skip(offset).take(4).toList();
      final responses = await Future.wait(batch.map((plugin) async {
        try {
          return await plugin.queryBangumi(keyword, shouldRethrow: true);
        } catch (_) {
          return null;
        }
      }));
      if (!mounted || generation != _generation) return;
      for (var i = 0; i < batch.length; i++) {
        final response = responses[i];
        if (response == null) continue;
        final matches = response.data
            .where((hit) => _sameWork(hit.name, item))
            .toList(growable: false);
        for (final hit in matches) {
          if (await trySaved(batch[i].name, hit.name, hit.src)) return;
        }
      }
    }
    if (mounted && generation == _generation) {
      setState(() {
        _loading = false;
        _error = '未找到能解析真实集数的默认来源，请点右上角「其他来源」手动选择';
      });
    }
  }

  void _play(int episode) {
    final plugin = _selectedPlugin;
    if (plugin == null || !_ready) return;
    final road = _roads[_roadIndex];
    if (episode < 1 || episode > road.data.length) return;
    setState(() => _episode = episode);
    context.pushNamed(
      '/video/',
      arguments: OnlineVideoPlaybackArgs(
        bangumiItem: widget.infoController.bangumiItem,
        plugin: plugin,
        title: _sourceTitle,
        src: _sourceUrl,
        roads: _roads,
        initialRoad: _roadIndex,
        initialEpisode: episode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final road = _ready ? _roads[_roadIndex] : null;
    final count = road?.data.length ?? 0;
    final pages = (count + pageSize - 1) ~/ pageSize;
    final first = _page * pageSize;
    final last = (first + pageSize).clamp(0, count).toInt();
    return Padding(
      key: const ValueKey('suibo-episode-section'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('选集', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 10),
              if (_ready)
                Expanded(
                  child: Text(
                    '${_selectedPlugin!.name} · 共$count集',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              IconButton(
                key: const ValueKey('suibo-reload-episodes'),
                tooltip: '重新获取选集',
                onPressed: _loading ? null : _loadDefault,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!_ready)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_error ?? '暂无可用集数'),
            )
          else ...[
            if (_roads.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < _roads.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_roads[index].name.isEmpty
                              ? '线路${index + 1}'
                              : _roads[index].name),
                          selected: index == _roadIndex,
                          onSelected: (_) {
                            final progress = _history.lastWatching(
                                widget.infoController.bangumiItem,
                                _selectedPlugin!.name);
                            final resume = progress?.road == index
                                ? (progress?.episode ?? 1)
                                : 1;
                            setState(() {
                              _roadIndex = index;
                              _episode = resume.clamp(
                                  1, _roads[index].data.length).toInt();
                              _page = (_episode - 1) ~/ pageSize;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            if (pages > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SingleChildScrollView(
                  key: const ValueKey('suibo-episode-range-tabs'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0; index < pages; index++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('suibo-range-$index'),
                            label: Text(
                                '${index * pageSize + 1}-${((index + 1) * pageSize).clamp(0, count)}'),
                            selected: _page == index,
                            onSelected: (_) => setState(() => _page = index),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            LayoutBuilder(builder: (context, box) {
              final columns = box.maxWidth >= 900
                  ? 8
                  : box.maxWidth >= 560
                      ? 6
                      : 3;
              return GridView.builder(
                key: const ValueKey('suibo-episode-grid'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: last - first,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: box.maxWidth >= 560 ? 2.8 : 2.2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final episode = first + index + 1;
                  final label = first + index < road!.identifier.length &&
                          road.identifier[first + index].trim().isNotEmpty
                      ? road.identifier[first + index]
                      : '第$episode集';
                  final active = _episode == episode;
                  return FilledButton.tonal(
                    key: ValueKey('suibo-episode-$episode'),
                    style: FilledButton.styleFrom(
                      backgroundColor: active
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHigh,
                      foregroundColor: active
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                    onPressed: () => _play(episode),
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  );
                },
              );
            }),
          ],
        ],
      ),
    );
  }
}
