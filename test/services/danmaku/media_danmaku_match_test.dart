import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/services/danmaku/media_danmaku_service.dart';

void main() {
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
}
