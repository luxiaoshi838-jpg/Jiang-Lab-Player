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
    expect(item.summary, contains('不是播放链接'));
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
