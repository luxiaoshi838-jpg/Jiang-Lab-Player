import 'package:dio/dio.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// TMDB supplies metadata and identity, never a video stream.
class TmdbCatalogService {
  static const sourceName = 'TMDB';
  static const imageBase = 'https://image.tmdb.org/t/p/w500';

  static int? tmdbIdFromItem(BangumiItem item) {
    if (item.sourcePlugin != sourceName) return null;
    final uri = Uri.tryParse(item.sourceUrl);
    if (uri == null || uri.host != 'www.themoviedb.org') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 2 ||
        (segments.first != 'movie' && segments.first != 'tv')) return null;
    return int.tryParse(segments.last);
  }

  static List<BangumiItem> parseSearchResults(Map<String, dynamic> json) {
    final raw = json['results'];
    if (raw is! List) return [];
    final items = <BangumiItem>[];
    final ids = <String>{};
    for (final entry in raw) {
      if (entry is! Map) continue;
      final kind = entry['media_type']?.toString() ?? '';
      if (kind != 'tv' && kind != 'movie') continue;
      if (entry['adult'] == true) continue;
      final id = entry['id'];
      if (id is! int || id <= 0) continue;
      final key = '$kind:$id';
      if (!ids.add(key)) continue;
      final name = (entry[kind == 'tv' ? 'name' : 'title'] ?? '')
          .toString().trim();
      final original = (entry[kind == 'tv' ? 'original_name' : 'original_title'] ?? '')
          .toString().trim();
      if (name.isEmpty && original.isEmpty) continue;
      final link = 'https://www.themoviedb.org/$kind/$id';
      final title = name.isEmpty ? original : name;
      final item = BangumiItem.fromRule(
        pluginName: sourceName,
        source: link,
        title: title,
      );
      item.name = original.isEmpty ? title : original;
      item.nameCn = title;
      item.summary = (entry['overview'] ?? '').toString();
      if (item.summary.isEmpty) {
        item.summary = 'TMDB 作品资料（非视频播放源）';
      }
      final date = (entry[kind == 'tv' ? 'first_air_date' : 'release_date'] ?? '')
          .toString();
      item.airDate = date;
      final poster = (entry['poster_path'] ?? '').toString();
      if (poster.startsWith('/') && !poster.startsWith('//')) {
        final image = '$imageBase$poster';
        item.images = {
          'large': image,
          'common': image,
          'medium': image,
          'small': image,
          'grid': image,
        };
      }
      final votes = entry['vote_average'];
      if (votes is num) item.ratingScore = votes.toDouble();
      items.add(item);
    }
    return items;
  }

  static Future<List<BangumiItem>> search(String keyword) async {
    final query = keyword.trim();
    final credential =
        GStorage.getSetting(SettingsKeys.tmdbReadAccessToken).trim();
    if (query.isEmpty || credential.isEmpty) return [];
    try {
      final result = await DioFactory.apiDio.get(
        'https://api.themoviedb.org/3/search/multi',
        queryParameters: <String, dynamic>{
          'query': query,
          'language': 'zh-CN',
          'include_adult': false,
          'page': 1,
        },
        options: Options(headers: {
          'Authorization': 'Bearer $credential',
          'accept': 'application/json',
        }),
      ).timeout(const Duration(seconds: 9));
      if (result.data is! Map) return [];
      return parseSearchResults(
          Map<String, dynamic>.from(result.data as Map));
    } catch (error) {
      KazumiLogger().w('TmdbCatalogService: catalog search unavailable',
          error: error);
      return [];
    }
  }
}
