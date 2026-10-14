import 'dart:convert';
import 'dart:io';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/popular/home_media_category.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/video_source/default_cms_sources.dart';

/// Browse REAL CMS category lists instead of treating "movie" or "TV" as a
/// Bangumi subject tag. A CMS listing carries actual cover, work kind and
/// stable vod_id used by the existing playback source-sheet.
class CmsHomeCatalog {
  static const int maxResponseBytes = 1024 * 1024;
  static const int maxPagesPerCategory = 5;

  static bool isAdultLabel(String label) =>
      RegExp(r'伦理|福利|成人|无码|情色|写真|三级片|擦边').hasMatch(label);

  static bool kindMatches(HomeMediaCategory kind, String label) {
    if (label.isEmpty || isAdultLabel(label)) return false;
    if (kind == HomeMediaCategory.anime) return false;
    if (kind == HomeMediaCategory.variety) {
      return label.contains('综艺') || label.contains('真人秀') ||
          label.contains('娱乐节目');
    }
    if (kind == HomeMediaCategory.shortDrama) {
      return label.contains('短剧') || label.contains('微剧');
    }
    if (label.contains('短剧') || label.contains('微短') ||
        label.contains('动漫') || label.contains('动画') ||
        label.contains('综艺') || label.contains('真人秀') ||
        label.contains('娱乐节目')) {
      return false;
    }
    if (kind == HomeMediaCategory.movie) {
      return label.contains('电影') ||
          (label.endsWith('片') && !label.contains('剧'));
    }
    return label.contains('电视剧') || label.contains('连续剧') ||
        label.contains('剧集') || label.contains('国产剧') ||
        label.contains('欧美剧') || label.contains('日韩剧') ||
        label.contains('港剧') || label.endsWith('剧');
  }

  static List<Map<String, String>> categories(dynamic payload) {
    if (payload is! Map || payload['class'] is! List) return const [];
    final items = <Map<String, String>>[];
    for (final row in payload['class'] as List) {
      if (row is! Map) continue;
      final id = (row['type_id'] ?? '').toString().trim();
      final label = (row['type_name'] ?? '').toString().trim();
      if (id.isEmpty || label.isEmpty || isAdultLabel(label)) continue;
      items.add({
        'id': id,
        'name': label,
        'parent': (row['type_pid'] ?? '0').toString(),
      });
    }
    return items;
  }

  /// Includes nested "都市剧" under "电视剧", if supplied by the CMS.
  static List<Map<String, String>> matchingCategories(
      HomeMediaCategory kind, String tag, List<Map<String, String>> all) {
    final byId = {for (final entry in all) entry['id']: entry};
    final roots = all.where((row) => kindMatches(kind, row['name'] ?? ''))
        .where((row) => row['parent'] == '0' ||
            !byId.containsKey(row['parent']))
        .toList();
    final related = all.where((row) {
      var current = row;
      final visited = <String>{};
      while (true) {
        if (roots.any((root) => root['id'] == current['id'])) return true;
        final parentId = current['parent'] ?? '';
        if (!visited.add(parentId) || parentId == '0') return false;
        final parent = byId[parentId];
        if (parent == null) return false;
        current = parent;
      }
    }).toList();
    // Some feeds flatten the taxonomy and have no root '电影'/'电视剧'.
    final candidates = related.isEmpty
        ? all.where((x) => kindMatches(kind, x['name'] ?? '')).toList()
        : related;
    if (tag.isEmpty) return candidates;
    final tagged = candidates.where((x) => genreMatches(
        tag, x['name'] ?? '')).toList();
    // Search both a tag-specific CMS category and metadata-labeled rows in
    // the broad category; no cross-kind fallback.
    return [
      ...tagged,
      ...candidates.where((x) => !tagged.contains(x)),
    ];
  }

  static bool genreMatches(String genre, String text) {
    if (genre.isEmpty) return true;
    if (text.contains(genre)) return true;
    const alternatives = {
      '搞笑': ['喜剧'],
      '甜宠': ['甜宠', '甜蜜', '甜剧'],
      '都市': ['都市', '现代都市'],
      '青春': ['青春', '校园'],
      '古装': ['古装', '古代'],
    };
    return (alternatives[genre] ?? const <String>[])
        .any(text.contains);
  }

  static bool rowMatches(HomeMediaCategory kind, String tag,
      Map row, String categoryName) {
    final typeName = (row['type_name'] ?? categoryName).toString();
    // Never allow an explicit CMS item kind to override its section.
    // A short-drama list sometimes includes ordinary TV show rows.
    final foreignKinds = HomeMediaCategory.values.where(
        (value) => value != kind && value != HomeMediaCategory.anime);
    if (foreignKinds.any((value) => kindMatches(value, typeName))) {
      return false;
    }
    final genres = [
      (row['vod_class'] ?? '').toString(),
      (row['vod_tag'] ?? '').toString(),
      typeName,
      categoryName,
    ].join(',');
    if (isAdultLabel(genres)) { return false; }
    if (kind == HomeMediaCategory.shortDrama &&
        !kindMatches(kind, typeName) &&
        !kindMatches(kind, categoryName)) { return false; }
    if (kind != HomeMediaCategory.shortDrama &&
        (typeName.contains('短剧') || typeName.contains('微短'))) { return false; }
    return genreMatches(tag, genres);
  }

  static List<BangumiItem> parseItems(
      dynamic data, Plugin source, HomeMediaCategory kind,
      String tag, String categoryName) {
    if (data is! Map || data['list'] is! List) return const [];
    final result = <BangumiItem>[];
    for (final row in data['list'] as List) {
      if (row is! Map || !rowMatches(kind, tag, row, categoryName)) continue;
      final title = (row['vod_name'] ?? '').toString().trim();
      final id = (row['vod_id'] ?? '').toString().trim();
      if (title.isEmpty || id.isEmpty) continue;
      final cover = (row['vod_pic'] ?? '').toString().trim();
      final url = Uri.tryParse(cover);
      final imageUrl = url != null &&
          (url.scheme == 'http' || url.scheme == 'https') &&
          url.host.isNotEmpty && url.userInfo.isEmpty ? cover : '';
      final item = BangumiItem.fromRule(
          pluginName: source.name, source: id,
          title: title, imageUrl: imageUrl);
      item.summary = (row['vod_remarks'] ?? row['vod_content'] ?? '')
          .toString().replaceAll(RegExp(r'<[^>]+>'), '').trim();
      result.add(item);
    }
    return result;
  }

  static Uri _withQuery(String endpoint, Map<String, String> params) =>
      Uri.parse(endpoint).replace(queryParameters: params);

  static Future<dynamic> _readJson(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri)
        .timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close()
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return null;
    final chunks = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 6))) {
      chunks.addAll(chunk);
      if (chunks.length > maxResponseBytes) return null;
    }
    try {
      return jsonDecode(utf8.decode(chunks));
    } catch (_) {
      return null;
    }
  }

  static Future<List<BangumiItem>> load({
    required HomeMediaCategory category,
    required String subcategory,
    required Iterable<Plugin> installedSources,
    int count = 24,
    HttpClient? client,
  }) async {
    if (category == HomeMediaCategory.anime) return const [];
    final owned = client == null;
    final http = client ?? (HttpClient()
      ..connectionTimeout = const Duration(seconds: 5));
    try {
      final sources = installedSources.where((plugin) =>
          plugin.name.startsWith('CMS · ') &&
          plugin.baseUrl.startsWith('https://')).take(4).toList();
      if (sources.isEmpty) {
        sources.addAll(await DefaultCmsSources.fetch());
      }
      final found = <BangumiItem>[];
      final seen = <String>{};
      for (final source in sources) {
        try {
          final schema = await _readJson(http,
              _withQuery(source.baseUrl, {'ac': 'list'}));
          final categoryList = matchingCategories(
              category, subcategory, categories(schema));
          for (final group in categoryList.take(6)) {
            for (var page = 1; page <= maxPagesPerCategory; page++) {
              final data = await _readJson(http, _withQuery(source.baseUrl, {
                'ac': 'videolist',
                't': group['id']!,
                'pg': '$page',
              }));
              final items = parseItems(data, source, category,
                  subcategory, group['name']!);
              // Most CMS list endpoints omit vod_class. Fetch the real detail
              // metadata once per page before deciding a genre has no hits.
              if (subcategory.isNotEmpty &&
                  !genreMatches(subcategory, group['name']!) &&
                  data is Map && data['list'] is List) {
                final ids = (data['list'] as List).whereType<Map>()
                    .map((row) => (row['vod_id'] ?? '').toString().trim())
                    .where((id) => id.isNotEmpty)
                    .take(20).join(',');
                if (ids.isNotEmpty) {
                  final details = await _readJson(http,
                      _withQuery(source.baseUrl, {
                    'ac': 'videolist', 'ids': ids,
                  }));
                  items.addAll(parseItems(details, source, category,
                      subcategory, group['name']!));
                }
              }
              for (final item in items) {
                final key = item.nameCn.toLowerCase();
                if (seen.add(key)) { found.add(item); }
                if (found.length >= count) {
                  return found;
                }
              }
              if (data is! Map || data['list'] is! List ||
                  (data['list'] as List).isEmpty) { break; }
              final pageCount = int.tryParse(
                  (data['pagecount'] ?? '').toString());
              if (pageCount != null && page >= pageCount) { break; }
            }
          }
        } catch (_) {
          // A failed CMS provider does not block other installed providers.
        }
      }
      return found;
    } finally {
      if (owned) http.close(force: true);
    }
  }
}
