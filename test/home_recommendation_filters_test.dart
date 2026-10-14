import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/popular/home_media_category.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/utils/constants.dart';

void main() {
  group('Independent home genre filters', () {
    test('anime retains the existing tag set', () {
      expect(HomeMediaCategory.anime.subcategories, defaultAnimeTags);
      expect(HomeMediaCategory.anime.popularTitle, '热门番剧');
      final params = BangumiApi.buildHomeRecommendationParams(
        category: HomeMediaCategory.anime,
        workKindTag: '',
        subcategory: '日常',
      );
      expect(params['sort'], 'heat');
      expect((params['filter'] as Map)['type'], [2]);
      expect((params['filter'] as Map)['tag'], ['日常']);
    });

    test('movies never use a TV or unfiltered genre query', () {
      final params = BangumiApi.buildHomeRecommendationParams(
        category: HomeMediaCategory.movie,
        workKindTag: '电影',
        subcategory: '悬疑',
      );
      expect((params['filter'] as Map)['type'], [6]);
      expect((params['filter'] as Map)['tag'], ['电影', '悬疑']);
    });

    test('TV has its own labels, including comedy, urban and history', () {
      final series = HomeMediaCategory.series;
      expect(series.subcategories, containsAll(['剧情', '搞笑', '都市', '历史']));
      for (final kind in series.genreTags) {
        final params = BangumiApi.buildHomeRecommendationParams(
          category: series,
          workKindTag: kind,
          subcategory: '历史',
        );
        expect((params['filter'] as Map)['tag'], [kind, '历史']);
      }
    });

    test('short dramas require a short-drama identity as well as genre', () {
      final short = HomeMediaCategory.shortDrama;
      for (final kind in short.genreTags) {
        final params = BangumiApi.buildHomeRecommendationParams(
          category: short,
          workKindTag: kind,
          subcategory: '都市',
        );
        expect((params['filter'] as Map)['tag'], [kind, '都市']);
      }
    });

    test('variety genres have an independent valid catalogue scope', () {
      expect(HomeMediaCategory.values.length, 5);
      expect(HomeMediaCategory.variety.genreTags, contains('综艺'));
      expect(HomeMediaCategory.variety.subcategories, contains('真人秀'));
    });

    test('each section has its own distinct default query', () {
      final signatures = <String>{};
      for (final category in HomeMediaCategory.values) {
        final params = BangumiApi.buildHomeRecommendationParams(
          category: category,
          workKindTag: category.genreTags.isEmpty
              ? ''
              : category.genreTags.first,
        );
        final filter = params['filter'] as Map;
        signatures.add('${filter['type']}|${filter['tag']}');
      }
      expect(signatures.length, HomeMediaCategory.values.length);
    });

    test('a tag from another menu cannot be mixed into the wrong kind', () {
      expect(
        () => BangumiApi.buildHomeRecommendationParams(
          category: HomeMediaCategory.movie,
          workKindTag: '电视剧',
          subcategory: '动作',
        ),
        throwsArgumentError,
      );
      expect(
        () => BangumiApi.buildHomeRecommendationParams(
          category: HomeMediaCategory.shortDrama,
          workKindTag: '短剧',
          subcategory: '机战',
        ),
        throwsArgumentError,
      );
    });

    test('five sections support expandable 24-item batches', () {
      expect(HomeMediaCategory.pageSize, 24);
      expect(HomeMediaCategory.values.map((x) => x.popularTitle).toList(),
          ['热门番剧', '热门电影', '热门电视剧', '热门短剧', '热门综艺']);
    });
  });
}
