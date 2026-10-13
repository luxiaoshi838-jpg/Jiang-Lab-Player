import 'dart:convert';
import 'dart:io';

import 'package:kazumi/plugins/plugins.dart';

/// Data-only CMS auto-discovery. Never runs TVBox JS/JAR or remote code.
///
/// Community feeds describe interfaces, not ownership or licensing of videos.
/// Each episode is still subject to its provider's access and playback rights.
class DefaultCmsSources {
  static const catalogUrl =
      'https://raw.githubusercontent.com/25175/tvyuan/master/tvbox.json';
  static const maxSources = 4;
  static const maxCatalogBytes = 256 * 1024;

  static final RegExp _excludedNames = RegExp(
    r'18\+|成人|情色|福利|麻豆|精东|无码|色情|91|番号|情色|精品自拍|[^\w]19(?:[^\w]|$)',
    caseSensitive: false,
  );

  static String? _cmsEndpoint(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        InternetAddress.tryParse(uri.host) != null ||
        uri.host.endsWith('.local') || uri.host == 'localhost' ||
        uri.query.isNotEmpty || uri.fragment.isNotEmpty ||
        !uri.path.toLowerCase().contains('/api.php/provide/vod')) {
      return null;
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), '')).toString();
  }

  /// Deterministic, conservative subset: only API type=1, no adult categories,
  /// no private-network URL, no duplicate host. API records have no scripts.
  static List<Plugin> parse(Object? raw) {
    if (raw is! Map || raw['sites'] is! List) return const <Plugin>[];
    final result = <Plugin>[];
    final hosts = <String>{};
    for (final site in raw['sites'] as List) {
      if (site is! Map || site['type'] != 1) continue;
      if (site['searchable'] == 0 || site['quickSearch'] == 0) continue;
      final name = (site['name'] ?? '').toString().trim();
      if (name.isEmpty || _excludedNames.hasMatch(name)) continue;
      final endpoint = _cmsEndpoint(site['api']);
      if (endpoint == null) continue;
      final host = Uri.parse(endpoint).host.toLowerCase();
      if (!hosts.add(host)) continue;
      final displayName = 'CMS · ' +
          (site['key'] ?? host).toString().replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '');
      result.add(createPlugin(name: displayName, endpoint: endpoint));
      if (result.length >= maxSources) break;
    }
    return result;
  }

  static Plugin createPlugin({required String name, required String endpoint}) {
    if (_cmsEndpoint(endpoint) != endpoint) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Expected a public HTTPS CMS V10 API');
    }
    return Plugin.fromJson(<String, dynamic>{
      'api': '8',
      'name': name,
      'type': 'video',
      'version': '1.0',
      'muliSources': true,
      'useWebview': false,
      'useNativePlayer': true,
      'baseURL': endpoint,
      'searchMode': 'api',
      'chapterMode': 'api',
      'searchApiConfig': <String, dynamic>{
        'request': <String, dynamic>{
          'method': 'GET',
          'url': endpoint,
          'query': <String, dynamic>{'ac': 'videolist', 'wd': '@keyword'},
        },
        'listPath': r'$.list[*]',
        'namePath': r'$.vod_name',
        'sourcePath': r'$.vod_id',
        'imagePath': r'$.vod_pic',
      },
      'chapterApiConfig': <String, dynamic>{
        'request': <String, dynamic>{
          'method': 'GET',
          'url': endpoint,
          'query': <String, dynamic>{'ac': 'videolist', 'ids': '@source'},
        },
        'format': 'delimited',
        'roadNamesPath': r'$.list[0].vod_play_from',
        'roadEpisodesPath': r'$.list[0].vod_play_url',
        'roadSeparator': r'$$$',
        'episodeSeparator': '#',
        'fieldSeparator': r'$',
      },
    });
  }

  static Future<List<Plugin>> fetch({HttpClient? client}) async {
    final http = client ?? (HttpClient()
      ..connectionTimeout = const Duration(seconds: 5));
    try {
      final request = await http.getUrl(Uri.parse(catalogUrl))
          .timeout(const Duration(seconds: 6));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close()
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const <Plugin>[];
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 6))) {
        bytes.addAll(chunk);
        if (bytes.length > maxCatalogBytes) return const <Plugin>[];
      }
      return parse(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      return const <Plugin>[];
    } finally {
      if (client == null) http.close(force: true);
    }
  }
}
