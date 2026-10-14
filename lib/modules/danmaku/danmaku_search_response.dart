import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';

/// Search results from official DanDanPlay or a configured compatible API.
/// IDs belong to the service which returned them and are not interchangeable.
class DanmakuSearchAnime {
  final int animeId;
  final String animeTitle;
  final String typeDescription;
  final bool compatibleProvider;
  /// Episode identities returned by /search/episodes. Do not discard them
  /// and then require an unrelated second catalog request.
  final List<DanmakuEpisode> episodes;

  const DanmakuSearchAnime({
    required this.animeId,
    required this.animeTitle,
    required this.typeDescription,
    this.compatibleProvider = false,
    this.episodes = const [],
  });

  static DanmakuSearchAnime? parse(
    dynamic raw, {
    bool compatibleProvider = false,
  }) {
    if (raw is! Map) return null;
    final id = int.tryParse('${raw['animeId'] ?? ''}');
    final title = (raw['animeTitle'] ?? '').toString().trim();
    if (id == null || id <= 0 || title.isEmpty) return null;
    final episodeRows = raw['episodes'];
    final parsedEpisodes = <DanmakuEpisode>[];
    if (episodeRows is List) {
      for (final row in episodeRows) {
        if (row is! Map) continue;
        try {
          parsedEpisodes.add(
            DanmakuEpisode.fromJson(Map<String, dynamic>.from(row)),
          );
        } on FormatException {
          // Keep usable episodes even when a source sends one invalid row.
        }
      }
    }
    return DanmakuSearchAnime(
      animeId: id,
      animeTitle: title,
      typeDescription: (raw['typeDescription'] ?? '').toString(),
      compatibleProvider: compatibleProvider,
      episodes: parsedEpisodes,
    );
  }

  factory DanmakuSearchAnime.fromJson(Map<String, dynamic> json) {
    final value = parse(json);
    if (value == null) {
      throw const FormatException('Invalid danmaku search entry');
    }
    return value;
  }
}

class DanmakuSearchResponse {
  final List<DanmakuSearchAnime> animes;
  final bool hasMore;

  const DanmakuSearchResponse({
    required this.animes,
    required this.hasMore,
  });

  factory DanmakuSearchResponse.fromJson(
    Map<String, dynamic> json, {
    bool compatibleProvider = false,
  }) {
    if (json['success'] == false) {
      throw const FormatException('Danmaku provider rejected search');
    }
    final rows = json['animes'];
    if (rows is! List) {
      throw const FormatException('Danmaku search missing animes list');
    }
    return DanmakuSearchResponse(
      animes: [
        for (final item in rows)
          if (DanmakuSearchAnime.parse(
            item,
            compatibleProvider: compatibleProvider,
          ) case final DanmakuSearchAnime anime)
            anime,
      ],
      hasMore: json['hasMore'] == true,
    );
  }
}
