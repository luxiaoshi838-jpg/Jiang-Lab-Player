import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/danmaku.dart';

/// Recorded Bilibili BV/av videos, never Bilibili live rooms.
class BilibiliVideoRef {
  const BilibiliVideoRef({this.bvid, this.aid, required this.page});

  final String? bvid;
  final int? aid;
  final int page;

  static BilibiliVideoRef? fromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    const hosts = {'bilibili.com', 'www.bilibili.com', 'm.bilibili.com'};
    if (!hosts.contains(uri.host.toLowerCase())) return null;
    final segments = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (segments.length != 2 || segments.first != 'video') return null;
    final id = segments.last;
    final page = int.tryParse(uri.queryParameters['p'] ?? '1') ?? 1;
    if (page < 1) return null;
    if (RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(id)) {
      return BilibiliVideoRef(bvid: id, page: page);
    }
    if (RegExp(r'^av[1-9][0-9]*$', caseSensitive: false).hasMatch(id)) {
      return BilibiliVideoRef(aid: int.tryParse(id.substring(2)), page: page);
    }
    return null;
  }

  Map<String, dynamic> get viewParams => {
        if (bvid != null) 'bvid': bvid,
        if (aid != null) 'aid': aid,
      };
}

class MediaDanmakuMatch {
  const MediaDanmakuMatch(this.entries, {this.dandanId = 0});

  final List<DanmakuEntry> entries;
  final int dandanId;
}

/// Reuse Kazumi's existing canvas, timing, filtering and manual source picker.
/// Only on-demand VOD is supported; no live room/chat protocol is added.
class MediaDanmakuService {
  static Future<MediaDanmakuMatch?> match({
    required String title,
    required int episode,
    required Iterable<String> pageUrls,
    Iterable<String> titleAliases = const <String>[],
    String episodeTitle = '',
  }) async {
    // Native CID is an exact identity for a single Bilibili video page.
    for (final url in pageUrls) {
      final reference = BilibiliVideoRef.fromUrl(url);
      if (reference == null) continue;
      try {
        final native = await fetchBilibili(reference);
        if (native.isNotEmpty) return MediaDanmakuMatch(native);
      } catch (error) {
        KazumiLogger().w('MediaDanmaku: Bilibili video comments unavailable',
            error: error);
      }
      break;
    }

    // A work must have a unique identity. Search a small number of supplied
    // titles (rather than guessing a different show or downloading catalogs).
    // Always load the explicit episodeId from the server's episode list.
    final searched = <String>{};
    for (final query in <String>[title, ...titleAliases]) {
      final normalized = normalizeTitle(query);
      if (normalized.isEmpty || !searched.add(normalized)) continue;
      if (searched.length > 3) {
        break;
      }
      try {
        final candidates = await DanmakuApi.searchAnimes(query.trim());
        final chosen = selectAnime(candidates, query);
        if (chosen == null) continue;
        final details =
            await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(chosen.animeId);
        final episodeId = selectEpisodeId(
          details.episodes,
          episode,
          episodeTitle: episodeTitle,
        );
        if (episodeId == null) continue;
        final comments = await DanmakuApi.getDanDanmakuByEpisodeID(episodeId);
        if (comments.isNotEmpty) {
          return MediaDanmakuMatch(comments, dandanId: chosen.animeId);
        }
      } catch (error) {
        KazumiLogger().w(
          'MediaDanmaku: title/episode match unavailable',
          error: error,
        );
      }
    }
    final communityMatch = await _matchCommunity(
      title: title,
      titleAliases: titleAliases,
      episode: episode,
      episodeTitle: episodeTitle,
      pageUrls: pageUrls,
    );
    return communityMatch;
  }

  /// A DanDanPlay-compatible community aggregator provides movie, drama and
  /// variety comments not indexed by the original animation-oriented API.
  /// Override with --dart-define=SUIBO_DANMU_API_URL=https://your-server
  static const String communityDanmakuApi = String.fromEnvironment(
    'SUIBO_DANMU_API_URL',
    defaultValue: 'https://api.danmu.icu',
  );

  static Uri? communityUri(String path, [Map<String, String>? query]) {
    final base = Uri.tryParse(communityDanmakuApi.trim());
    if (base == null || base.host.isEmpty ||
        (base.scheme != 'https' && base.scheme != 'http')) {
      return null;
    }
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1) : base.path;
    return base.replace(path: '$prefix$path', queryParameters: query);
  }

  static List<DanmakuEntry> parseCommunityComments(dynamic data) {
    final List<dynamic>? raw = data is List
        ? data
        : data is Map && data['comments'] is List
            ? data['comments'] as List<dynamic>
            : null;
    if (raw == null) return const [];
    final result = <DanmakuEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final entry = DanmakuEntry.fromJson(Map<String, dynamic>.from(item));
        if (entry.message.trim().isNotEmpty && entry.time.isFinite &&
            entry.time >= 0) {
          result.add(entry);
        }
      } catch (_) {
        // One invalid comment must not discard the entire episode.
      }
    }
    return result;
  }

  static Future<dynamic> _communityGet(
      String path, Map<String, String> query) async {
    final uri = communityUri(path, query);
    if (uri == null) return null;
    return (await DioFactory.apiDio.getUri(uri,
      options: Options(receiveTimeout: const Duration(seconds: 8)),
    ).timeout(const Duration(seconds: 10))).data;
  }

  static Future<MediaDanmakuMatch?> _matchCommunity({
    required String title,
    required Iterable<String> titleAliases,
    required Iterable<String> pageUrls,
    required String episodeTitle,
    required int episode,
  }) async {
    // Only first-party VOD page URLs are shared with the aggregator.
    // Never send signed stream links or third-party rule page URLs.
    const videoHosts = {
      'v.qq.com', 'www.iqiyi.com', 'www.mgtv.com',
      'v.youku.com', 'www.bilibili.com', 'www.miguvideo.com',
    };
    for (final url in pageUrls) {
      final page = Uri.tryParse(url.trim());
      if (page == null || page.scheme != 'https' ||
          !videoHosts.contains(page.host.toLowerCase())) continue;
      try {
        // The public danmu.icu server uses a different, XML-based URL API.
        // A self-hosted danmu_api instance exposes DanDanPlay JSON endpoints.
        if (Uri.parse(communityDanmakuApi).host == 'api.danmu.icu') {
          final uri = communityUri('/', {'ac': 'dm', 'url': page.toString()});
          if (uri != null) {
            final response = await DioFactory.apiDio.getUri(
              uri,
              options: Options(responseType: ResponseType.plain,
                  receiveTimeout: const Duration(seconds: 8)),
            ).timeout(const Duration(seconds: 10));
            final comments = parseBilibiliXml(response.data.toString());
            if (comments.isNotEmpty) {
              return MediaDanmakuMatch(comments);
            }
          }
        } else {
          final data = await _communityGet('/api/v2/comment',
              {'url': page.toString(), 'format': 'json'});
          final comments = parseCommunityComments(data);
          if (comments.isNotEmpty) {
            return MediaDanmakuMatch(comments);
          }
        }
      } catch (error) {
        KazumiLogger().w('CommunityDanmaku: URL lookup failed', error: error);
      }
    }

    final searched = <String>{};
    for (final candidate in <String>[title, ...titleAliases]) {
      final query = candidate.trim();
      if (query.isEmpty || !searched.add(normalizeTitle(query))) continue;
      if (searched.length > 3) break;
      try {
        final rawSearch = await _communityGet(
            '/api/v2/search/episodes', {'anime': query, 'episode': '$episode'});
        if (rawSearch is! Map || rawSearch['animes'] is! List) continue;
        final response = DanmakuSearchResponse.fromJson(
            Map<String, dynamic>.from(rawSearch));
        final show = selectAnime(response, query);
        if (show == null) continue;
        final rawDetail = await _communityGet(
            '/api/v2/bangumi/${show.animeId}', const {});
        if (rawDetail is! Map || rawDetail['bangumi'] is! Map) continue;
        final detail = DanmakuEpisodeResponse.fromJson(
            Map<String, dynamic>.from(rawDetail));
        final episodeId = selectEpisodeId(
            detail.episodes, episode, episodeTitle: episodeTitle);
        if (episodeId == null) continue;
        final comments = parseCommunityComments(await _communityGet(
            '/api/v2/comment/$episodeId', const {'format': 'json'}));
        if (comments.isNotEmpty) {
          return MediaDanmakuMatch(comments, dandanId: show.animeId);
        }
      } catch (error) {
        KazumiLogger().w('CommunityDanmaku: episode lookup failed',
            error: error);
      }
    }
    return null;
  }

  /// Normalize harmless presentation differences, never strip seasons or
  /// edition words indiscriminately.
  static String normalizeTitle(String title) {
    final ascii = title.replaceAllMapped(
      RegExp(r'[\uFF01-\uFF5E]'),
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
    );
    return ascii.toLowerCase().replaceAll(
      RegExp(r'[\s_\-—–·:：.。!！?？《》〈〉\[\]【】（）(),，、]'),
      '',
    );
  }

  static int? _season(String normalized) {
    final match = _seasonSuffix.firstMatch(normalized);
    if (match == null) return null;
    final value = match.group(1) ?? match.group(2) ?? match.group(3)!;
    const chinese = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
    };
    return int.tryParse(value) ?? chinese[value];
  }

  static final RegExp _seasonSuffix = RegExp(
    r'(?:第([0-9一二三四五六七八九十]+)季|season0*([0-9]+)|s0*([0-9]+))$',
  );

  static bool titlesMatch(String requested, String found) {
    final a = normalizeTitle(requested);
    final b = normalizeTitle(found);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final aSeason = _season(a);
    final bSeason = _season(b);
    if (aSeason == null && bSeason == null) return false;
    // An unlabelled work may represent season one, but never guess later
    // seasons. Multiple season-one candidates remain ambiguous below.
    if (aSeason != bSeason &&
        !(aSeason == null && bSeason == 1) &&
        !(bSeason == null && aSeason == 1)) {
      return false;
    }
    final aBase = a.replaceFirst(_seasonSuffix, '');
    final bBase = b.replaceFirst(_seasonSuffix, '');
    return aBase.isNotEmpty && aBase == bBase;
  }

  /// Never silently select from duplicated titles or a truncated result set.
  static DanmakuSearchAnime? selectAnime(
    DanmakuSearchResponse response,
    String title,
  ) {
    if (response.hasMore) return null;
    final unique = <int, DanmakuSearchAnime>{};
    for (final candidate in response.animes) {
      if (titlesMatch(title, candidate.animeTitle)) {
        unique[candidate.animeId] = candidate;
      }
    }
    return unique.length == 1 ? unique.values.single : null;
  }

  static String? _date(String title) {
    final match = RegExp(
      r'(20[0-9]{2})[年./-](0?[1-9]|1[0-2])[月./-](0?[1-9]|[12][0-9]|3[01])日?',
    ).firstMatch(title);
    if (match == null) return null;
    final year = match.group(1)!;
    final month = match.group(2)!.padLeft(2, '0');
    final day = match.group(3)!.padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _edition(String title) {
    for (final marker in <String>['加更', '纯享', '特别', '番外', '花絮', '先导']) {
      if (title.contains(marker)) return marker;
    }
    return '正片';
  }

  static int? _episodeNumber(String title) {
    final chinese = RegExp(r'第\s*0*([0-9]{1,4})\s*[集话期]').firstMatch(title);
    if (chinese != null) return int.tryParse(chinese.group(1)!);
    final english = RegExp(
      r'(?:^|[\s_.-])(?:ep|episode|e)\s*0*([0-9]{1,4})(?:\b|$)',
      caseSensitive: false,
    ).firstMatch(title);
    return english == null ? null : int.tryParse(english.group(1)!);
  }

  /// Only bind a confidently identified episode. A numeric position in an
  /// unordered/variant episode list is not a reliable episode identity.
  static int? selectEpisodeId(
    List<DanmakuEpisode> entries,
    int episode, {
    String episodeTitle = '',
  }) {
    if (episode < 1 || entries.isEmpty) return null;
    final requestedEdition = _edition(episodeTitle);
    final requestedDate = _date(episodeTitle);
    final matches = entries.where((entry) {
      if (_edition(entry.episodeTitle) != requestedEdition) return false;
      if (requestedDate != null) return _date(entry.episodeTitle) == requestedDate;
      return _episodeNumber(entry.episodeTitle) == episode;
    }).toList();
    if (matches.length == 1) return matches.single.episodeId;
    if (matches.isNotEmpty || requestedDate != null) return null;
    // A movie or a genuinely single-part work has an unambiguous lone entry.
    if (episode == 1 && entries.length == 1 &&
        _edition(entries.single.episodeTitle) == requestedEdition &&
        _episodeNumber(entries.single.episodeTitle) == null) {
      return entries.single.episodeId;
    }
    return null;
  }

  static Future<List<DanmakuEntry>> fetchBilibili(
      BilibiliVideoRef video) async {
    final view = await DioFactory.apiDio.get(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: video.viewParams,
      options: Options(headers: {'referer': 'https://www.bilibili.com/'}),
    ).timeout(const Duration(seconds: 10));
    final json = view.data;
    if (json is! Map || json['code'] != 0 || json['data'] is! Map) return [];
    final data = json['data'] as Map;
    final rawPages = data['pages'];
    int? cid;
    if (rawPages is List) {
      if (video.page > rawPages.length) return [];
      final requested = rawPages[video.page - 1];
      if (requested is Map) cid = (requested['cid'] as num?)?.toInt();
    } else if (video.page == 1) {
      cid = (data['cid'] as num?)?.toInt();
    }
    if (cid == null || cid <= 0) return [];
    final response = await DioFactory.apiDio.get(
      'https://comment.bilibili.com/$cid.xml',
      options: Options(
        responseType: ResponseType.plain,
        headers: {'referer': 'https://www.bilibili.com/'},
      ),
    ).timeout(const Duration(seconds: 10));
    return parseBilibiliXml(response.data.toString());
  }

  /// Bilibili uses time,mode,font,color,...; DanDanPlay uses another layout.
  static List<DanmakuEntry> parseBilibiliXml(String xml) {
    final parsed = html_parser.parse(xml);
    final entries = <DanmakuEntry>[];
    for (final element in parsed.querySelectorAll('d[p]')) {
      final parts = (element.attributes['p'] ?? '').split(',');
      if (parts.length < 4) continue;
      final time = double.tryParse(parts[0]);
      final mode = int.tryParse(parts[1]);
      final rgb = int.tryParse(parts[3]);
      if (time == null || !time.isFinite || time < 0 ||
          mode == null || rgb == null) {
        continue;
      }
      // Do not run unsupported advanced or reverse modes as ordinary text.
      if (mode != 1 && mode != 4 && mode != 5) continue;
      final message = element.text.trim();
      if (message.isEmpty) continue;
      entries.add(DanmakuEntry(
        message: message,
        time: time,
        type: mode,
        color: generateDanmakuColor(rgb),
        source: 'BiliBili',
      ));
    }
    return entries;
  }
}
