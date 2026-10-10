import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
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
    int? tmdbId,
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

    // TMDB IDs can match multiple season-specific comment libraries.
    // Only auto-load if precisely one distinct library matches; ambiguous
    // series must be selected using the untouched manual source picker.
    if (tmdbId != null && tmdbId > 0) {
      try {
        final response = await DanmakuApi.searchByTmdbId(tmdbId, episode);
        final unique = {for (final anime in response.animes) anime.animeId};
        if (response.hasMore || unique.length != 1) return null;
        final id = unique.single;
        final info = await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(id);
        if (episode < 1 || episode > info.episodes.length) return null;
        final episodeId = info.episodes[episode - 1].episodeId;
        final entries = await DanmakuApi.getDanDanmakuByEpisodeID(episodeId);
        return entries.isEmpty ? null : MediaDanmakuMatch(entries, dandanId: id);
      } catch (error) {
        KazumiLogger().w('MediaDanmaku: TMDB mapping unavailable',
            error: error);
        return null;
      }
    }

    // Fallback requires exactly one strictly identical work title. Never
    // attach ambiguous or partial matches to a possibly different timeline.
    final normalized = normalizeTitle(title);
    if (normalized.isEmpty) return null;
    try {
      final candidates = await DanmakuApi.searchAnimes(title.trim());
      final matched = candidates.animes.where(
        (e) => normalizeTitle(e.animeTitle) == normalized,
      ).toList();
      if (matched.length != 1) return null;
      final chosen = matched.single;
      final details =
          await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(chosen.animeId);
      if (episode < 1 || episode > details.episodes.length) return null;
      final episodeId = details.episodes[episode - 1].episodeId;
      final comments = await DanmakuApi.getDanDanmakuByEpisodeID(episodeId);
      if (comments.isEmpty) return null;
      return MediaDanmakuMatch(comments, dandanId: chosen.animeId);
    } catch (error) {
      KazumiLogger().w('MediaDanmaku: exact title match unavailable',
          error: error);
      return null;
    }
  }

  static String normalizeTitle(String title) =>
      title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

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
          mode == null || rgb == null) continue;
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
