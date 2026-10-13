import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/public_video_catalog.dart';

void main() {
  Map<String, dynamic> page(String title, List<String> cats) => {
    'query': {
      'pages': [
        {'pageid': 123, 'ns': 0, 'title': title,
          'categories': [for (final c in cats) {'title': 'Category:$c'}]}
      ]
    }
  };
  test('一饭封神 catalog hit is not a video source', () {
    final item = PublicVideoCatalog.parseExactTitle(
        page('一饭封神', ['2025年中国大陆综艺节目']), '一饭封神');
    expect(item, isNotNull);
    expect(item!.name, '一饭封神');
    expect(item.isExternal, isTrue);
    expect(item.summary, contains('暂无剧情简介'));
  });
  test('encyclopedia extracts become real description, not fake playback link', () {
    final data = page('亮剑', ['中国大陆电视剧']);
    final pages = (data['query'] as Map)['pages'] as List;
    (pages.first as Map)['extract'] = '《亮剑》是中国大陆电视剧。';
    (pages.first as Map)['thumbnail'] = {
      'source': 'https://upload.wikimedia.org/example.jpg'
    };
    final item = PublicVideoCatalog.parseExactTitle(data, '亮剑');
    expect(item, isNotNull);
    expect(item!.summary, contains('中国大陆电视剧'));
    expect(item.summary, contains('维基百科'));
    expect(item.images['large'], contains('https://'));
    expect(item.isExternal, isTrue);
  });
  test('both historical dramas qualify', () {
    for (final title in ['亮剑', '大明王朝1566']) {
      expect(PublicVideoCatalog.parseExactTitle(
          page(title, ['中国大陆电视剧']), title), isNotNull);
    }
  });
  test('rejects unrelated, missing, and live-only pages', () {
    expect(PublicVideoCatalog.parseExactTitle(
        page('亮剑', ['军事史']), '亮剑'), isNull);
    expect(PublicVideoCatalog.parseExactTitle(
        page('另一部剧', ['中国大陆电视剧']), '亮剑'), isNull);
    expect(PublicVideoCatalog.isVideoCategory(['Category:网络直播']),
        isFalse);
    expect(PublicVideoCatalog.parseExactTitle({
      'query': {'pages': [{'ns': 0, 'title': '一饭封神', 'missing': true}]}
    }, '一饭封神'), isNull);
  });
}
