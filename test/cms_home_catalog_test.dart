import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/popular/home_media_category.dart';
import 'package:kazumi/services/video_source/cms_home_catalog.dart';
import 'package:kazumi/services/video_source/default_cms_sources.dart';

void main() {
  final source = DefaultCmsSources.createPlugin(
    name: 'CMS · 影视目录',
    endpoint: 'https://example.org/api.php/provide/vod',
  );
  final taxonomy = CmsHomeCatalog.categories({
    'class': [
      {'type_id': 1, 'type_name': '电影', 'type_pid': 0},
      {'type_id': 2, 'type_name': '国产剧', 'type_pid': 0},
      {'type_id': 3, 'type_name': '短剧', 'type_pid': 0},
      {'type_id': 4, 'type_name': '动作片', 'type_pid': 1},
      {'type_id': 5, 'type_name': '都市剧', 'type_pid': 2},
      {'type_id': 6, 'type_name': '伦理', 'type_pid': 0},
      {'type_id': 7, 'type_name': '综艺', 'type_pid': 0},
      {'type_id': 8, 'type_name': '真人秀', 'type_pid': 7},
    ],
  });

  test('CMS work types form separate movie TV and short-drama catalogs', () {
    final movie = CmsHomeCatalog.matchingCategories(
        HomeMediaCategory.movie, '', taxonomy);
    final tv = CmsHomeCatalog.matchingCategories(
        HomeMediaCategory.series, '', taxonomy);
    final short = CmsHomeCatalog.matchingCategories(
        HomeMediaCategory.shortDrama, '', taxonomy);
    expect(movie.map((x) => x['id']), containsAll(['1', '4']));
    expect(tv.map((x) => x['id']), containsAll(['2', '5']));
    expect(short.map((x) => x['id']), ['3']);
    expect(movie.map((x) => x['id']), isNot(contains('3')));
    expect(tv.map((x) => x['id']), isNot(contains('3')));
  });

  test('variety returns real variety CMS categories, never movie or TV', () {
    final variety = CmsHomeCatalog.matchingCategories(
        HomeMediaCategory.variety, '', taxonomy);
    expect(variety.map((x) => x['id']), containsAll(['7', '8']));
    expect(variety.map((x) => x['id']), isNot(contains('2')));
    expect(CmsHomeCatalog.kindMatches(HomeMediaCategory.series, '真人秀'), isFalse);
    final rows = CmsHomeCatalog.parseItems({
      'list': [
        {'vod_id': '432', 'vod_name': '示例节目', 'type_name': '综艺'},
        {'vod_id': '433', 'vod_name': '电视剧', 'type_name': '国产剧'},
      ]
    }, source, HomeMediaCategory.variety, '', '综艺');
    expect(rows.map((e) => e.sourceUrl), ['432']);
  });

  test('switching a genre prioritizes its matching catalog category', () {
    final tv = CmsHomeCatalog.matchingCategories(
        HomeMediaCategory.series, '都市', taxonomy);
    expect(tv.first['id'], '5');
    expect(CmsHomeCatalog.genreMatches('搞笑', '喜剧'), isTrue);
    expect(CmsHomeCatalog.genreMatches('历史', '动作'), isFalse);
  });

  test('real CMS metadata creates a playable rule entry with cover', () {
    final items = CmsHomeCatalog.parseItems({
      'list': [{
        'vod_id': '88123', 'vod_name': '示例都市剧',
        'vod_pic': 'https://images.example.org/cover.jpg',
        'type_name': '国产剧', 'vod_class': '都市,剧情',
        'vod_remarks': '更新至第八集',
      }, {
        'vod_id': '999', 'vod_name': '其他题材',
        'type_name': '国产剧', 'vod_class': '历史',
      }]
    }, source, HomeMediaCategory.series, '都市', '国产剧');
    expect(items.length, 1);
    expect(items.single.sourcePlugin, source.name);
    expect(items.single.sourceUrl, '88123');
    expect(items.single.isExternal, isTrue);
    expect(items.single.images['large'],
        'https://images.example.org/cover.jpg');
  });

  test('unrelated episodes and inappropriate genres cannot backfill', () {
    final items = CmsHomeCatalog.parseItems({
      'list': [
        {'vod_id': 1, 'vod_name': '普通长剧', 'type_name': '电视剧'},
        {'vod_id': 2, 'vod_name': '不应推荐', 'type_name': '伦理'},
      ]
    }, source, HomeMediaCategory.shortDrama, '', '短剧');
    expect(items, isEmpty);
  });

  test('short-drama category with a real type and matching subgenre stays', () {
    final items = CmsHomeCatalog.parseItems({
      'list': [
        {'vod_id': 100, 'vod_name': '一部短剧',
         'type_name': '短剧', 'vod_class': '逆袭,都市'},
      ]
    }, source, HomeMediaCategory.shortDrama, '逆袭', '短剧');
    expect(items.length, 1);
  });
}
