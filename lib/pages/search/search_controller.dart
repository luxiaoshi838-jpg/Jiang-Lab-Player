import 'dart:io';

import 'package:mobx/mobx.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/media_source_candidate.dart';
import 'package:kazumi/services/video_source/media_work_index.dart';
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
import 'package:kazumi/services/video_source/tvmaze_catalog_service.dart';

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
      for (final item in newItems) {
        MediaWorkIndex.addMetadata(bangumiList, item);
      }
      if (newItems.isNotEmpty) break;
    } while (hasMoreSearchResults && pagesFetched < _maxPagesPerSearch);
    // Resolve metadata before merging rule hits, so a catalog/real Bangumi
    // subject remains the single detail entry for each confidently matched
    // title. Catalog providers are metadata only, never playable URLs.
    if (type != 'add' &&
        filterState.keyword.trim().isNotEmpty &&
        !filterState.hasAdvancedFilters) {
      final title = filterState.keyword.trim();
      final alreadyIndexed = bangumiList.any((item) =>
          MediaWorkIndex.sameWork(item, title));
      if (!alreadyIndexed) {
        final wiki = await PublicVideoCatalog.findExactVideo(title);
        if (generation != _searchGeneration) return;
        if (wiki != null) MediaWorkIndex.addMetadata(bangumiList, wiki);
        if (wiki == null) {
          final tvmaze = await TvmazeCatalogService.search(title);
          if (generation != _searchGeneration) return;
          for (final show in tvmaze) {
            MediaWorkIndex.addMetadata(bangumiList, show);
          }
        }
      }
      await _appendRuleResults(title, generation);
    }
    if (generation != _searchGeneration) return;
    isLoading = false;
    isTimeOut = bangumiList.isEmpty;
  }

  Future<void> _appendRuleResults(String keyword, int generation) async {
    final rules = _pluginsController.pluginList
        .where((rule) => !isLiveOnlyRule(rule.type))
        .toList(growable: false);
    // Never deduplicate by title before retaining its rule URL: separate
    // providers can legitimately serve the same work.
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
              isKnownLivePage(result.src)) {
            continue;
          }
          MediaWorkIndex.addRuleHit(bangumiList, MediaSourceCandidate(
            pluginName: batch[i].name,
            title: title,
            url: result.src,
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
