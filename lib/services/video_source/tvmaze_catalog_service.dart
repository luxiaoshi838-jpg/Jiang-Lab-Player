import 'package:html/parser.dart' as html_parser;
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';

/// Anonymous public TVmaze metadata API: https://www.tvmaze.com/api
/// TVmaze data is CC BY-SA; the result keeps the provider link and credit.
/// This service never fetches or invents playable media URLs.
class TvmazeCatalogService {
  static const sourceName = 'TVmaze节目目录';

  static String normalizeTitle(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static List<BangumiItem> parseResults(dynamic body, String keyword) {
    if (body is! List) return [];
    final matches = <BangumiItem>[];
    final seen = <String>{};
    for (final raw in body) {
      if (raw is! Map || raw['show'] is! Map) continue;
      final show = raw['show'] as Map;
      final title = (show['name'] ?? '').toString().trim();
      final id = show['id'];
      final website = (show['url'] ?? '').toString();
      final uri = Uri.tryParse(website);
      if (title.isEmpty || id is! int || id <= 0 ||
          normalizeTitle(title) != normalizeTitle(keyword) ||
          uri == null || uri.scheme != 'https' ||
          !{'www.tvmaze.com', 'tvmaze.com'}.contains(uri.host)) {
        continue; // Avoid attaching a merely fuzzy result to another show.
      }
      if (!seen.add('$id')) continue;
      final item = BangumiItem.fromRule(
        pluginName: sourceName,
        source: website,
        title: title,
      );
      final summary = (show['summary'] ?? '').toString();
      final description = html_parser.parseFragment(summary).text.trim();
      item.summary = description.isNotEmpty
          ? '$description\n资料：TVmaze（非视频播放源）'
          : '节目资料由 TVmaze 提供（非视频播放源）';
      item.airDate = (show['premiered'] ?? '').toString();
      final image = show['image'];
      if (image is Map) {
        final cover = (image['medium'] ?? image['original'] ?? '').toString();
        if (cover.startsWith('https://')) {
          item.images = {
            'large': cover, 'common': cover, 'medium': cover,
            'small': cover, 'grid': cover,
          };
        }
      }
      matches.add(item);
    }
    return matches;
  }

  static Future<List<BangumiItem>> search(String keyword) async {
    final name = keyword.trim();
    if (name.isEmpty || name.length > 90) return const [];
    try {
      final response = await DioFactory.apiDio.get(
        'https://api.tvmaze.com/search/shows',
        queryParameters: {'q': name},
      ).timeout(const Duration(seconds: 7));
      return parseResults(response.data, name);
    } catch (error) {
      KazumiLogger().w('TvmazeCatalogService: lookup unavailable',
          error: error);
      return const [];
    }
  }
}
