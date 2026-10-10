import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';

/// Independent metadata lookup for recorded video programmes.
class PublicVideoCatalog {
  static const sourceName = '百科影视目录';
  static const categoryTerms = <String>[
    '电视剧', '電視劇', '电视节目', '電視節目',
    '综艺', '綜藝', '真人秀', '电影', '電影',
    '动画', '動畫', '纪录片', '紀錄片', '短剧', '短劇',
    '网剧', '網劇', '网络剧', '網絡劇', '網路劇',
    '网络节目', '網路節目', '网络综艺', '網路綜藝',
    '影集', '網路影集', '网络视频', '網路影片',
  ];

  static bool isVideoCategory(Iterable<String> categories) =>
      categories.any((c) => categoryTerms.any(c.contains));

  static BangumiItem? parseExactTitle(
      Map<String, dynamic> data, String keyword) {
    final query = data['query'];
    if (query is! Map || query['pages'] is! List) return null;
    for (final raw in query['pages'] as List) {
      if (raw is! Map || raw['missing'] == true ||
          raw['ns'] != 0 || raw['pageid'] is! int) continue;
      final cats = raw['categories'];
      if (cats is! List ||
          !isVideoCategory(cats.whereType<Map>().map(
              (c) => c['title']?.toString() ?? ''))) continue;
      final title = raw['title']?.toString().trim() ?? '';
      if (title.isEmpty) continue;
      final requested = keyword.trim().replaceAll(' ', '').toLowerCase();
      final canonical = title.replaceAll(' ', '').toLowerCase();
      final redirects = query['redirects'];
      final alias = redirects is List && redirects.any((r) =>
          r is Map && r['to'] == title &&
          r['from']?.toString().replaceAll(' ', '').toLowerCase() == requested);
      if (requested != canonical && !alias) continue;
      final url = Uri.https(
          'zh.wikipedia.org', '/wiki/' + title.replaceAll(' ', '_'))
          .toString();
      final item = BangumiItem.fromRule(
          pluginName: sourceName, source: url, title: keyword.trim());
      item.summary = '百科作品资料（不是播放链接），播放仍需可用来源规则';
      final image = raw['thumbnail'];
      if (image is Map && image['source'] is String) {
        final thumb = image['source'] as String;
        item.images = {'large': thumb, 'common': thumb,
          'medium': thumb, 'small': thumb, 'grid': thumb};
      }
      return item;
    }
    return null;
  }

  static Future<BangumiItem?> findExactVideo(String keyword) async {
    final title = keyword.trim();
    if (title.isEmpty || title.length > 80) return null;
    try {
      final result = await DioFactory.apiDio.get(
        'https://zh.wikipedia.org/w/api.php',
        queryParameters: <String, dynamic>{
          'action': 'query', 'format': 'json', 'formatversion': 2,
          'redirects': '1', 'prop': 'categories|pageimages',
          'cllimit': 'max', 'piprop': 'thumbnail',
          'pithumbsize': 300, 'titles': title,
        },
      ).timeout(const Duration(seconds: 8));
      final data = result.data;
      return data is Map
          ? parseExactTitle(Map<String, dynamic>.from(data), title)
          : null;
    } catch (error) {
      KazumiLogger().w('PublicVideoCatalog: lookup failed', error: error);
      return null;
    }
  }
}
