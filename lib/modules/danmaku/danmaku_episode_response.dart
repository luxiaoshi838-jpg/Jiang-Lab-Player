/// A stable episode identifier and an optional explicit numeric order.
/// Compatible backends may label an episode as "正片" but still supply
/// episodeNumber = "1" in their JSON representation.
class DanmakuEpisode {
  int episodeId;
  String episodeTitle;
  int? episodeNumber;

  DanmakuEpisode({
    required this.episodeId,
    required this.episodeTitle,
    this.episodeNumber,
  });

  factory DanmakuEpisode.fromJson(Map<String, dynamic> json) {
    final id = int.tryParse(json['episodeId'].toString());
    if (id == null || id <= 0) {
      throw const FormatException('Invalid danmaku episodeId');
    }
    return DanmakuEpisode(
      episodeId: id,
      episodeTitle: (json['episodeTitle'] ?? '').toString(),
      episodeNumber: int.tryParse((json['episodeNumber'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'episodeId': episodeId,
        'episodeTitle': episodeTitle,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
      };
}

class DanmakuEpisodeResponse {
  int bangumiId;
  List<DanmakuEpisode> episodes;
  int errorCode;
  bool success;
  String errorMessage;

  DanmakuEpisodeResponse({
    required this.bangumiId,
    required this.episodes,
    required this.errorCode,
    required this.success,
    required this.errorMessage,
  });

  factory DanmakuEpisodeResponse.fromJson(Map<String, dynamic> json) {
    if (json['success'] == false) {
      throw const FormatException('Danmaku episode service rejected request');
    }
    final rawBangumi = json['bangumi'];
    if (rawBangumi is! Map || rawBangumi['episodes'] is! List) {
      throw const FormatException('Invalid danmaku bangumi detail');
    }
    final id = int.tryParse((rawBangumi['animeId'] ?? '').toString()) ?? 0;
    final episodes = <DanmakuEpisode>[
      for (final raw in rawBangumi['episodes'])
        if (raw is Map<String, dynamic>) DanmakuEpisode.fromJson(raw),
    ];
    return DanmakuEpisodeResponse(
      bangumiId: id,
      episodes: episodes,
      errorCode: int.tryParse((json['errorCode'] ?? 0).toString()) ?? 0,
      success: json['success'] == true,
      errorMessage: (json['errorMessage'] ?? '').toString(),
    );
  }

  factory DanmakuEpisodeResponse.fromTemplate() {
    return DanmakuEpisodeResponse(
      bangumiId: 0,
      episodes: [],
      errorCode: 0,
      success: false,
      errorMessage: '',
    );
  }

  Map<String, dynamic> toJson() => {
        'bangumi': {
          'animeId': bangumiId,
          'episodes': [for (final episode in episodes) episode.toJson()],
        },
        'errorCode': errorCode,
        'success': success,
        'errorMessage': errorMessage,
      };
}
