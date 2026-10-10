import 'dart:io';

import 'package:mobx/mobx.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/search/image_search_module.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/apis/trace_api.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/utils/search_parser.dart';
import 'package:kazumi/services/video_source/video_catalog_scope.dart';
import 'package:kazumi/services/video_source/public_video_catalog.dart';
import 'package:kazumi/services/video_source/tmdb_catalog_service.dart';

part 'search_controller.g.dart';

class SearchPageController = _SearchPageController with _$SearchPageController;

abstract class _SearchPageController with Store {
  static const int _searchPageSize = 20;
  static const int _maxPagesPerSearch = 3;

  _SearchPageController(
    this._collectRepository,
    this._searchHistoryRepository,
    this._pluginsController,
  );

  final ICollectRepository _collectRepository;
  final ISearchHistoryRepository _searchHistoryRepository;
  final PluginsController _pluginsController;

  int _searchOffset = 0;
  int _searchGeneration = 0;

  bool hasMoreSearchResults = true;

  int get installedVideoRuleCount => _pluginsController.pluginList
      .where((p) => !isLiveOnlyRule(p.type)).length;

  @observable
  bool isLoading = false;

  @observable
  bool isTimeOut = false;

  @observable
  bool notShowWatchedBangumis = false;

  @observable
  bool notShowAbandonedBangumis = false;

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<SearchHistory> searchHistories = ObservableList.of([]);

  @observable
  bool isImageSearching = false;

  @observable
  String imageSearchError = '';

  @observable
  ObservableList<ResultItem> imageSearchResults = ObservableList.of([]);

  @action
  void loadSearchHistories() {
    final histories = _searchHistoryRepository.getAllHistories();
    searchHistories.clear();
    searchHistories.addAll(histories);
  }

  @action
  Future<void> searchBangumi(String input, {String type = 'add'}) async {
    if (type == 'add' && (isLoading || !hasMoreSearchResults)) return;
    final generation = type == 'add' ? _searchGeneration : ++_searchGeneration;
    isLoading = true;
    isTimeOut = false;
    if (type != 'add') {
      bangumiList.clear();
      _searchOffset = 0;
      hasMoreSearchResults = true;
      if (!_collectRepository.getPrivateMode() && input.trim().isNotEmpty) {
        await _searchHistoryRepository.deleteDuplicates(input);
        if (_searchHistoryRepository.isHistoryFull(10)) {
          await _searchHistoryRepository.deleteOldest();
        }
        await _searchHistoryRepository.saveHistory(input);
        loadSearchHistories();
      }
    }
    if (generation != _searchGeneration) return;
    final filterState = SearchParser(input).toFilterState();
    final id = int.tryParse(filterState.id);
    if (id != null) {
      final item = await BangumiApi.getBangumiInfoByID(id);
      if (generation != _searchGeneration) return;
      if (item != null) {
        bangumiList.add(item);
      }
      hasMoreSearchResults = false;
      isLoading = false;
      isTimeOut = bangumiList.isEmpty;
      return;
    }
    var pagesFetched = 0;
    do {
      final page = await BangumiApi.bangumiSearch(filterState.keyword,
          tags: filterState.tags,
          limit: _searchPageSize,
          offset: _searchOffset,
          sort: filterState.sort,
          dateRange: filterState.effectiveDateRange,
          rankRange: filterState.rankRange,
          scoreRange: filterState.scoreRange,
          weekdays: filterState.weekdays);
      // Discard stale responses before mutating the current search.
      if (generation != _searchGeneration) return;
      if (page == null) {
        break;
      }
      pagesFetched++;
      _searchOffset += page.rawCount;
      hasMoreSearchResults = page.rawCount == _searchPageSize;
      final existingIds = bangumiList.map((item) => item.id).toSet();
      final newItems =
          page.items.where((item) => existingIds.add(item.id)).toList();
      if (newItems.isNotEmpty) {
        bangumiList.addAll(newItems);
        break;
      }
    } while (hasMoreSearchResults && pagesFetched < _maxPagesPerSearch);
    // Extend the original search grid using rule-provided titles for media
    // not indexed in Bangumi. Filters are applied only to metadata results:
    // a rule cannot reliably honour Bangumi tags, dates or ratings.
    if (type != 'add' &&
        filterState.keyword.trim().isNotEmpty &&
        !filterState.hasAdvancedFilters) {
      await _appendRuleResults(filterState.keyword.trim(), generation);
    }
    if (generation != _searchGeneration) return;
    // TMDB supplies movie/TV/variety metadata only when the user has
    // configured a read-only token. Preserve Bangumi's original subjects and
    // prefer already-found rule/subject items for the same localized title.
    if (type != 'add' &&
        filterState.keyword.trim().isNotEmpty &&
        !filterState.hasAdvancedFilters) {
      final tmdb = await TmdbCatalogService.search(filterState.keyword.trim());
      if (generation != _searchGeneration) return;
      final titles = <String>{
        for (final existing in bangumiList)
          existing.nameCn.trim().toLowerCase(),
        for (final existing in bangumiList)
          existing.name.trim().toLowerCase(),
      };
      final ids = bangumiList.map((e) => e.id).toSet();
      for (final item in tmdb) {
        final localized = item.nameCn.trim().toLowerCase();
        if (localized.isEmpty ||
            !titles.add(localized) ||
            !ids.add(item.id)) continue;
        bangumiList.add(item);
      }
    }
    if (generation != _searchGeneration) return;
    // Bangumi is not a complete index of documentaries, reality TV or VOD.
    // The fallback is verified *metadata*, never an invented stream URL.
    if (type != 'add' &&
        filterState.keyword.trim().isNotEmpty &&
        !filterState.hasAdvancedFilters &&
        !bangumiList.any((item) =>
            item.name.trim() == filterState.keyword.trim() ||
            item.nameCn.trim() == filterState.keyword.trim())) {
      final item = await PublicVideoCatalog.findExactVideo(
          filterState.keyword.trim());
      if (generation != _searchGeneration) return;
      if (item != null &&
          !bangumiList.any((existing) => existing.id == item.id)) {
        bangumiList.add(item);
      }
    }
    if (generation != _searchGeneration) return;
    isLoading = false;
    isTimeOut = bangumiList.isEmpty;
  }

  Future<void> _appendRuleResults(String keyword, int generation) async {
    final rules = _pluginsController.pluginList
        .where((rule) => !isLiveOnlyRule(rule.type))
        .toList(growable: false);
    // Avoid flooding many independent sites simultaneously.
    final knownTitles = <String>{
      for (final item in bangumiList)
        (item.nameCn.isNotEmpty ? item.nameCn : item.name)
            .trim().toLowerCase(),
      for (final item in bangumiList) item.name.trim().toLowerCase(),
    };
    for (var start = 0; start < rules.length; start += 4) {
      if (generation != _searchGeneration) return;
      final batch = rules.skip(start).take(4).toList();
      final responses = await Future.wait(batch.map((rule) async {
        try {
          return await rule.queryBangumi(keyword, shouldRethrow: true)
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          return null; // A broken rule must not break the main search.
        }
      }));
      if (generation != _searchGeneration) return;
      for (var i = 0; i < batch.length; i++) {
        final response = responses[i];
        if (response == null) continue;
        for (final result in response.data.take(30)) {
          final title = result.name.trim();
          if (title.isEmpty || result.src.trim().isEmpty ||
              isKnownLivePage(result.src)) continue;
          if (!knownTitles.add(title.toLowerCase())) continue;
          bangumiList.add(BangumiItem.fromRule(
            pluginName: batch[i].name,
            source: result.src,
            title: title,
          ));
        }
      }
    }
  }

  @action
  Future<void> deleteSearchHistory(SearchHistory history) async {
    await _searchHistoryRepository.deleteHistory(history);
    loadSearchHistories();
  }

  @action
  Future<void> clearSearchHistory() async {
    await _searchHistoryRepository.clearAllHistories();
    loadSearchHistories();
  }

  @action
  void clearImageSearchState() {
    isImageSearching = false;
    imageSearchError = '';
    imageSearchResults.clear();
  }

  @action
  Future<void> searchImageByFile(File imageFile) async {
    isImageSearching = true;
    imageSearchError = '';
    imageSearchResults.clear();
    try {
      final result = await TraceApi.searchAnimeByImageFile(imageFile);
      imageSearchResults.addAll(result.result ?? []);
      if (result.error != null && result.error!.isNotEmpty) {
        imageSearchError = result.error!;
      } else if (imageSearchResults.isEmpty) {
        imageSearchError = '未找到匹配结果';
      }
    } catch (e) {
      imageSearchError = '图片搜索失败，请稍后重试';
    } finally {
      isImageSearching = false;
    }
  }

  @action
  Future<void> searchImageByUrl(String imageUrl) async {
    isImageSearching = true;
    imageSearchError = '';
    imageSearchResults.clear();
    try {
      final result = await TraceApi.searchAnimeByImageUrl(imageUrl);
      imageSearchResults.addAll(result.result ?? []);
      if (result.error != null && result.error!.isNotEmpty) {
        imageSearchError = result.error!;
      } else if (imageSearchResults.isEmpty) {
        imageSearchError = '未找到匹配结果';
      }
    } catch (e) {
      imageSearchError = '图片搜索失败，请检查图片地址或稍后重试';
    } finally {
      isImageSearching = false;
    }
  }

  @action
  Future<void> setNotShowWatchedBangumis(bool value) async {
    notShowWatchedBangumis = value;
  }

  @action
  Future<void> setNotShowAbandonedBangumis(bool value) async {
    notShowAbandonedBangumis = value;
  }

  Set<int> loadWatchedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.watched);
  }

  Set<int> loadAbandonedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.abandoned);
  }
}
