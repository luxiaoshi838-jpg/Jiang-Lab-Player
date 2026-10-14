import 'dart:math';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/video_source/cms_home_catalog.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/home_media_category.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:mobx/mobx.dart';

part 'popular_controller.g.dart';

class PopularController = _PopularController with _$PopularController;

abstract class _PopularController with Store {
  static const int _trendPageSize = 24;
  int _trendOffset = 0;
  bool _homeRequested = false;

  /// Each section loads independently. No artificial entries or cross-genre
  /// backfill: a catalogue error must not display TV titles as short dramas.
  final ObservableMap<HomeMediaCategory, ObservableList<BangumiItem>> homeItems =
      ObservableMap.of({
    for (final section in HomeMediaCategory.values)
      section: ObservableList<BangumiItem>(),
  });
  final ObservableMap<HomeMediaCategory, bool> homeLoading =
      ObservableMap.of({
    for (final section in HomeMediaCategory.values) section: false,
  });
  final ObservableMap<HomeMediaCategory, bool> homeFailed =
      ObservableMap.of({
    for (final section in HomeMediaCategory.values) section: false,
  });

  final ObservableMap<HomeMediaCategory, bool> homeHasMore =
      ObservableMap.of({
    for (final section in HomeMediaCategory.values) section: true,
  });

  /// One independent selected genre and request token per home category.
  final ObservableMap<HomeMediaCategory, String> homeSelectedTags =
      ObservableMap.of({
    for (final category in HomeMediaCategory.values) category: '',
  });
  final Map<HomeMediaCategory, int> _homeGeneration = {
    for (final category in HomeMediaCategory.values) category: 0,
  };

  @observable
  String currentTag = '';

  @observable
  ObservableList<BangumiItem> bangumiList = ObservableList.of([]);

  @observable
  ObservableList<BangumiItem> trendList = ObservableList.of([]);

  double scrollOffset = 0.0;

  @observable
  bool isLoadingMore = false;

  @observable
  bool isTimeOut = false;

  bool get _bangumiMirrorEnabled =>
      BangumiAcceleration.current == BangumiAcceleration.mirror;

  @action
  Future<void> queryHomeRecommendations({bool force = false}) async {
    if (_homeRequested && !force) return;
    _homeRequested = true;
    await Future.wait(
      HomeMediaCategory.values.map((category) => refreshHomeSection(category)),
    );
  }

  Future<void> selectHomeSubcategory(
      HomeMediaCategory category, String subcategory) async {
    if (!category.supportsSubcategory(subcategory) ||
        homeSelectedTags[category] == subcategory) {
      return;
    }
    runInAction(() {
      homeSelectedTags[category] = subcategory;
      homeItems[category]!.clear();
    });
    await refreshHomeSection(category);
  }

  /// Load all five independent catalogues in expandable 24-item batches.
  Future<void> refreshHomeSection(HomeMediaCategory category,
      {bool append = false}) async {
    if (append &&
        (homeLoading[category] == true || homeHasMore[category] != true)) {
      return;
    }
    final generation = (_homeGeneration[category] ?? 0) + 1;
    _homeGeneration[category] = generation;
    final subcategory = homeSelectedTags[category] ?? '';
    final requested = (append ? homeItems[category]!.length : 0) +
        HomeMediaCategory.pageSize;
    runInAction(() {
      homeLoading[category] = true;
      homeFailed[category] = false;
    });
    try {
      var entries = category == HomeMediaCategory.anime
          ? await BangumiApi.getHomeRecommendations(
              category: category, subcategory: subcategory, count: requested)
          : await CmsHomeCatalog.load(
              category: category,
              subcategory: subcategory,
              installedSources: inject<PluginsController>().pluginList,
              count: requested);
      // A failed ranking endpoint can return [] for a valid anime tag.
      if (entries.isEmpty && category == HomeMediaCategory.anime) {
        entries = await BangumiApi.getBangumiMirrorPopularSubjects(
            tag: subcategory, limit: requested);
        if (entries.isEmpty && subcategory.isNotEmpty) {
          entries = await BangumiApi.getBangumiList(rank: 0, tag: subcategory);
        }
        if (entries.isEmpty && subcategory.isEmpty) {
          entries = await BangumiApi.getBangumiTrendsList(
              type: 2, limit: requested);
        }
        entries = entries.where((item) => item.type == 2).toList();
      }
      if (_homeGeneration[category] != generation) {
        return;
      }
      final seen = <int>{};
      final unique = entries.where((entry) => seen.add(entry.id)).toList();
      runInAction(() {
        homeItems[category]!
          ..clear()
          ..addAll(unique);
        homeFailed[category] = unique.isEmpty;
        homeHasMore[category] = unique.length >= requested;
      });
    } catch (_) {
      if (_homeGeneration[category] != generation) {
        return;
      }
      runInAction(() {
        homeFailed[category] = homeItems[category]!.isEmpty;
        homeHasMore[category] = false;
      });
    } finally {
      if (_homeGeneration[category] == generation) {
        runInAction(() => homeLoading[category] = false);
      }
    }
  }

  Future<void> loadMoreHomeSection(HomeMediaCategory category) =>
      refreshHomeSection(category, append: true);

  void setCurrentTag(String s) {
    currentTag = s;
  }

  void clearBangumiList() {
    bangumiList.clear();
  }

  @action
  Future<void> queryBangumiByTrend({String type = 'add'}) async {
    if (type == 'init') {
      trendList.clear();
      _trendOffset = 0;
    }
    isLoadingMore = true;
    final result = _bangumiMirrorEnabled
        ? await BangumiApi.getBangumiMirrorPopularSubjects(
            limit: _trendPageSize,
            offset: _trendOffset,
          )
        : await BangumiApi.getBangumiTrendsList(
            limit: _trendPageSize,
            offset: _trendOffset,
          );
    if (result.isNotEmpty) {
      _trendOffset += _trendPageSize;
    }
    final existingIds = trendList.map((item) => item.id).toSet();
    trendList.addAll(result.where((item) => existingIds.add(item.id)));
    isLoadingMore = false;
    isTimeOut = trendList.isEmpty;
  }

  @action
  Future<void> queryBangumiByTag({String type = 'add'}) async {
    if (type == 'init') {
      bangumiList.clear();
    }
    isLoadingMore = true;
    var tag = currentTag;
    var result = _bangumiMirrorEnabled
        ? await BangumiApi.getBangumiMirrorPopularSubjects(
            tag: tag,
            offset: bangumiList.length,
          )
        : await BangumiApi.getBangumiList(
            rank: Random().nextInt(8000) + 1,
            tag: tag,
          );
    bangumiList.addAll(result);
    isLoadingMore = false;
    isTimeOut = bangumiList.isEmpty;
  }
}
