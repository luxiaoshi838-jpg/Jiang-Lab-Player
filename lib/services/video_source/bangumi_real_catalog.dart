import 'package:dio/dio.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/video_source/media_work_index.dart';

/// Independent, anonymous backup for Chinese dramas and live-action works.
///
/// The usual Bangumi client is allowed to use ECH/mirrors. This method uses
/// ordinary HTTPS when that transport fails, BEFORE dropping to Wikipedia.
/// Only the official subject index is used, not an unverified poster URL.
class BangumiRealCatalog {
  static const endpoint = 'https://api.bgm.tv/v0/search/subjects';

  static Map<String, dynamic> searchBody(String title) => {
        'keyword': title.trim(),
        'sort': 'match',
        'filter': {
          'type': [6],
          'nsfw': false,
        },
      };

  static BangumiItem? exactItem(dynamic payload, String title) {
    if (payload is! Map || payload['data'] is! List) return null;
    final items = <BangumiItem>[];
    for (final entry in payload['data'] as List) {
      if (entry is! Map) continue;
      try {
        final item = BangumiItem.fromJson(Map<String, dynamic>.from(entry));
        if (item.type != 6 || item.id <= 0) continue;
        if (MediaWorkIndex.sameWork(item, title)) items.add(item);
      } catch (_) {
        // Skip a malformed entry, never invent an item or an image URL.
      }
    }
    // Ambiguous editions must be user-selected, not silently merged.
    return items.length == 1 ? items.single : null;
  }

  static Future<BangumiItem?> findExact(String title) async {
    final keyword = title.trim();
    if (keyword.isEmpty || keyword.length > 80) return null;
    try {
      final result = await DioFactory.apiDio.post<dynamic>(
        endpoint,
        data: searchBody(keyword),
        queryParameters: {'limit': 20, 'offset': 0},
        options: Options(headers: {
          'User-Agent':
              'Suibo/2.3.11 (+https://github.com/luxiaoshi838-jpg/Jiang-Lab-Player)',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        }),
      ).timeout(const Duration(seconds: 12));
      return exactItem(result.data, keyword);
    } catch (error) {
      KazumiLogger().w('BangumiRealCatalog: backup lookup unavailable',
          error: error);
      return null;
    }
  }
}
