import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/services/danmaku/media_danmaku_service.dart';

void main() {
  test('compatible provider alone enables automatic work-title search', () {
    expect(MediaDanmakuService.canAutoSearchTitles(
      officialConfigured: false, compatibleConfigured: true,
    ), isTrue);
    expect(MediaDanmakuService.canAutoSearchTitles(
      officialConfigured: true, compatibleConfigured: false,
    ), isTrue);
    expect(MediaDanmakuService.canAutoSearchTitles(
      officialConfigured: false, compatibleConfigured: false,
    ), isFalse);
  });

  test('compatible decorated drama titles match without matching another show', () {
    const works = DanmakuSearchResponse(
      animes: [
        DanmakuSearchAnime(
          animeId: 9001, animeTitle: '亮剑(2005)【电视剧】from 360',
          typeDescription: '电视剧', compatibleProvider: true,
        ),
        DanmakuSearchAnime(
          animeId: 9002, animeTitle: '新亮剑(2011)【电视剧】from 360',
          typeDescription: '电视剧', compatibleProvider: true,
        ),
      ],
      hasMore: false,
    );
    expect(MediaDanmakuService.selectAnime(works, '亮剑')?.animeId, 9001);
    expect(MediaDanmakuService.selectAnime(works, '新亮剑')?.animeId, 9002);
    expect(MediaDanmakuService.selectAnime(works, '亮剑2'), isNull);
  });

  test('same work from multiple sources can be tried automatically', () {
    const response = DanmakuSearchResponse(
      animes: [
        DanmakuSearchAnime(
          animeId: 100, animeTitle: '亮剑(2005)【电视剧】from 360',
          typeDescription: '电视剧', compatibleProvider: true,
        ),
        DanmakuSearchAnime(
          animeId: 101, animeTitle: '亮剑(2005)【电视剧】from qq',
          typeDescription: '电视剧', compatibleProvider: true,
        ),
        DanmakuSearchAnime(
          animeId: 120, animeTitle: '新亮剑(2011)【电视剧】from 360',
          typeDescription: '电视剧', compatibleProvider: true,
        ),
      ], hasMore: false,
    );
    expect(MediaDanmakuService.selectAnime(response, '亮剑'), isNull);
    expect(
      MediaDanmakuService.matchingSourceCandidates(response, '亮剑')
          .map((entry) => entry.animeId).toList(),
      [100, 101],
    );
  });

  test('conflicting release years do not trigger an automatic wrong edition', () {
    const response = DanmakuSearchResponse(
      animes: [
        DanmakuSearchAnime(
          animeId: 100, animeTitle: '亮剑(2005)【电视剧】from qq',
          typeDescription: '电视剧', compatibleProvider: true,
        ),
        DanmakuSearchAnime(
          animeId: 120, animeTitle: '亮剑(2011)【电视剧】from 360',
          typeDescription: '电视剧', compatibleProvider: true,
        ),
      ], hasMore: false,
    );
    expect(MediaDanmakuService.matchingSourceCandidates(response, '亮剑'), isEmpty);
  });

  test('work title matching tolerates punctuation without guessing seasons', () {
    expect(MediaDanmakuService.normalizeTitle('《一饭封神》'), '一饭封神');
    expect(MediaDanmakuService.titlesMatch('一饭封神 第一季', '一饭封神'), isTrue);
    expect(MediaDanmakuService.titlesMatch('一饭封神 S01', '一饭封神 第一季'), isTrue);
    expect(MediaDanmakuService.titlesMatch('一饭封神 第二季', '一饭封神'), isFalse);
    expect(MediaDanmakuService.titlesMatch('亮剑', '新亮剑'), isFalse);
  });

  test('only one exact show may be selected', () {
    final unique = DanmakuSearchResponse(
      animes: [
        const DanmakuSearchAnime(
          animeId: 12, animeTitle: '《一饭封神》', typeDescription: '综艺',
        ),
        const DanmakuSearchAnime(
          animeId: 34, animeTitle: '其他节目', typeDescription: '综艺',
        ),
      ],
      hasMore: false,
    );
    expect(MediaDanmakuService.selectAnime(unique, '一饭封神')?.animeId, 12);
    final ambiguous = DanmakuSearchResponse(
      animes: [
        ...unique.animes,
        const DanmakuSearchAnime(
          animeId: 35, animeTitle: '一饭封神 第一季', typeDescription: '综艺',
        ),
      ],
      hasMore: false,
    );
    expect(MediaDanmakuService.selectAnime(ambiguous, '一饭封神'), isNull);
    expect(MediaDanmakuService.selectAnime(
      DanmakuSearchResponse(animes: unique.animes, hasMore: true),
      '一饭封神',
    ), isNull);
  });

  test('episode identity skips extra editions and list ordering', () {
    final episodes = [
      DanmakuEpisode(episodeId: 4003, episodeTitle: '第3期 正片'),
      DanmakuEpisode(episodeId: 4001, episodeTitle: '第1期 正片'),
      DanmakuEpisode(episodeId: 4011, episodeTitle: '第1期 加更版'),
      DanmakuEpisode(episodeId: 4002, episodeTitle: '第2期 正片'),
    ];
    expect(MediaDanmakuService.selectEpisodeId(episodes, 1), 4001);
    expect(MediaDanmakuService.selectEpisodeId(
      episodes, 1, episodeTitle: '第1期 加更版',
    ), 4011);
    expect(MediaDanmakuService.selectEpisodeId(episodes, 3), 4003);
    expect(MediaDanmakuService.selectEpisodeId(episodes, 4), isNull);
  });

  test('real upstream platform-prefixed episode labels are selectable', () {
    final anime = [
      DanmakuEpisode(episodeId: 101, episodeTitle: '【youku】 第1集 凡人修仙传 01'),
      DanmakuEpisode(episodeId: 102, episodeTitle: '【youku】 第2集 凡人修仙传 02'),
    ];
    final drama = [
      DanmakuEpisode(episodeId: 201, episodeTitle: '【qq】 亮剑_01'),
      DanmakuEpisode(episodeId: 202, episodeTitle: '【qq】 亮剑_02'),
    ];
    expect(MediaDanmakuService.selectEpisodeId(anime, 1), 101);
    expect(MediaDanmakuService.selectEpisodeId(anime, 2), 102);
    expect(MediaDanmakuService.selectEpisodeId(drama, 1), 201);
    expect(MediaDanmakuService.selectEpisodeId(drama, 2), 202);
    expect(MediaDanmakuService.selectEpisodeId(drama, 3), isNull);
  });

  test('numeric episodeNumber from upstream selects an unlabelled drama entry', () {
    final detail = DanmakuEpisodeResponse.fromJson({
      'success': true, 'errorCode': 0, 'errorMessage': '',
      'bangumi': {
        'animeId': '9001',
        'episodes': [
          {'episodeId': '81001', 'episodeTitle': '正片', 'episodeNumber': '1'},
          {'episodeId': 81002, 'episodeTitle': '正片', 'episodeNumber': '2'},
        ],
      },
    });
    expect(detail.bangumiId, 9001);
    expect(MediaDanmakuService.selectEpisodeId(detail.episodes, 1), 81001);
    expect(MediaDanmakuService.selectEpisodeId(detail.episodes, 2), 81002);
    expect(MediaDanmakuService.selectEpisodeId(detail.episodes, 3), isNull);
  });

  test('date-labelled variety episodes match their actual date', () {
    final episodes = [
      DanmakuEpisode(episodeId: 501, episodeTitle: '2025-08-09 第1期'),
      DanmakuEpisode(episodeId: 502, episodeTitle: '2025-08-16 第2期'),
    ];
    expect(MediaDanmakuService.selectEpisodeId(
      episodes, 1, episodeTitle: '2025年8月9日',
    ), 501);
    expect(MediaDanmakuService.selectEpisodeId(
      episodes, 1, episodeTitle: '2025.8.16',
    ), 502);
    expect(MediaDanmakuService.selectEpisodeId(
      episodes, 1, episodeTitle: '2025-08-23',
    ), isNull);
  });

  test('uncertain episode lists require manual selection', () {
    final ambiguous = [
      DanmakuEpisode(episodeId: 10, episodeTitle: '第1集'),
      DanmakuEpisode(episodeId: 11, episodeTitle: '第1集'),
    ];
    expect(MediaDanmakuService.selectEpisodeId(ambiguous, 1), isNull);
    expect(MediaDanmakuService.selectEpisodeId([
      DanmakuEpisode(episodeId: 12, episodeTitle: '第1集 纯享版'),
    ], 1), isNull);
    expect(MediaDanmakuService.selectEpisodeId([
      DanmakuEpisode(episodeId: 13, episodeTitle: '电影正片'),
    ], 1), 13);
    expect(MediaDanmakuService.selectEpisodeId([
      DanmakuEpisode(episodeId: 14, episodeTitle: '无集数标识'),
      DanmakuEpisode(episodeId: 15, episodeTitle: '另一期'),
    ], 1), isNull);
  });

  test('Bilibili CID matching remains limited to recorded videos', () {
    expect(BilibiliVideoRef.fromUrl('https://www.bilibili.com/video/BV1234567890?p=2')?.page, 2);
    expect(BilibiliVideoRef.fromUrl('https://live.bilibili.com/1234'), isNull);
  });
  test('community API URL preserves a configured prefix and encodes query', () {
    final uri = MediaDanmakuService.communityUri(
      '/api/v2/search/episodes', {'anime': '生万物', 'episode': '2'});
    expect(uri, isNotNull);
    expect(uri!.queryParameters['anime'], '生万物');
    expect(uri.queryParameters['episode'], '2');
  });

  test('community response skips invalid comments without losing valid ones', () {
    final comments = MediaDanmakuService.parseCommunityComments({
      'comments': [
        {'m': '你好', 'p': '12.5,1,16777215,腾讯'},
        {'m': 'bad', 'p': 'invalid'},
        {'m': '世界', 'p': '13.0,5,16777215,爱奇艺'},
      ]
    });
    expect(comments.length, 2);
    expect(comments.first.message, '你好');
    expect(comments.last.time, 13);
  });

  test('public danmuku API returns timestamped messages', () {
    final comments = MediaDanmakuService.parsePublicDanmaku(
      '{"code":23,"danmuku":['
      '[321.483,"right","","1125690","你好","10-13 19:00","32px"],'
      '[322.0,"top","","16777215","第二条","","32px"]'
      ']}',
    );
    expect(comments.length, 2);
    expect(comments.first.time, 321.483);
    expect(comments.first.message, '你好');
    expect(comments.last.type, 5);
  });

  test('public library also supports Bilibili XML', () {
    final comments = MediaDanmakuService.parsePublicDanmaku(
        '<i><d p="5.0,1,25,16777215,0,0,0,0">弹幕</d></i>');
    expect(comments.length, 1);
    expect(comments.single.message, '弹幕');
  });

  test('danmu_api automatic match checks exact work and episode', () {
    final firstEpisode = {
      'animeTitle': '亮剑',
      'episodeTitle': '第1集',
      'episodeId': 8301,
    };
    final matched = {'isMatched': true, 'matches': [firstEpisode]};
    expect(MediaDanmakuService.selectCompatibleMatchId(matched, '亮剑', 1), 8301);
    expect(MediaDanmakuService.selectCompatibleMatchId({
      'isMatched': true,
      'matches': [{
        'animeTitle': '亮剑(2005)【电视剧】from 360',
        'episodeTitle': '第1集',
        'episodeId': 9001,
      }],
    }, '亮剑', 1), 9001);
    expect(MediaDanmakuService.selectCompatibleMatchId({
      'isMatched': true,
      'matches': [{
        'animeTitle': '新亮剑(2011)【电视剧】from 360',
        'episodeTitle': '第1集',
        'episodeId': 9002,
      }],
    }, '亮剑', 1), isNull);
    expect(MediaDanmakuService.selectCompatibleMatchId(matched, '亮剑', 2), isNull);
    expect(MediaDanmakuService.selectCompatibleMatchId(matched, '新亮剑', 1), isNull);
    expect(MediaDanmakuService.selectCompatibleMatchId({
      'isMatched': true,
      'matches': [firstEpisode, firstEpisode],
    }, '亮剑', 1), isNull);
    expect(MediaDanmakuService.selectCompatibleMatchId(
      {'isMatched': false, 'matches': matched['matches']}, '亮剑', 1,
    ), isNull);
    expect(MediaDanmakuService.selectCompatibleMatchId({
      'isMatched': true,
      'matches': [{'animeTitle': '亮剑', 'episodeTitle': '花絮',
        'episodeId': 8301}],
    }, '亮剑', 1), isNull);
  });

  test('classic mainland dramas use explicit numeric episode labels', () {
    final episodes = [
      DanmakuEpisode(episodeId: 7701, episodeTitle: '01'),
      DanmakuEpisode(episodeId: 7702, episodeTitle: '02'),
    ];
    expect(MediaDanmakuService.selectEpisodeId(episodes, 1), 7701);
    expect(MediaDanmakuService.selectEpisodeId(episodes, 2), 7702);
    expect(MediaDanmakuService.titlesMatch('亮剑', '《亮剑》'), isTrue);
    expect(MediaDanmakuService.titlesMatch(
      '知否知否应是绿肥红瘦', '知否知否应是绿肥红瘦'), isTrue);
  });

  test('public library URL accepts ordinary sources but not private links', () {
    expect(MediaDanmakuService.publicDanmakuVideoUrl(
      'https://cdn.example.com/tv/liangjian/01.m3u8'), isNotNull);
    expect(MediaDanmakuService.publicDanmakuVideoUrl(
      'https://v.qq.com/x/cover/abc/video.html'), isNotNull);
    expect(MediaDanmakuService.publicDanmakuVideoUrl(
      'https://cdn.example.com/01.m3u8?token=private'), isNull);
    expect(MediaDanmakuService.publicDanmakuVideoUrl(
      'https://127.0.0.1/video.mp4'), isNull);
    expect(MediaDanmakuService.publicDanmakuVideoUrl(
      'http://example.com/movie.m3u8'), isNull);
  });

}
