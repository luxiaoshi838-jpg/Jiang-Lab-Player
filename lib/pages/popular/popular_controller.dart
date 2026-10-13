import 'dart:math';
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

  Future<void> refreshHomeSection(HomeMediaCategory category) async {
    if (homeLoading[category] == true) return;
    runInAction(() {
      homeLoading[category] = true;
      homeFailed[category] = false;
    });
    try {
      final entries = await BangumiApi.getHomeRecommendations(
        subjectType: category.subjectType,
        genreTags: category.genreTags,
        count: HomeMediaCategory.visibleCount,
      );
      runInAction(() {
        final seen = <int>{};
        homeItems[category]!
          ..clear()
          ..addAll(entries.where((entry) => seen.add(entry.id)).take(
                HomeMediaCategory.visibleCount,
              ));
        homeFailed[category] = homeItems[category]!.isEmpty;
      });
    } catch (_) {
      runInAction(() => homeFailed[category] = true);
    } finally {
      runInAction(() => homeLoading[category] = false);
    }
  }

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
