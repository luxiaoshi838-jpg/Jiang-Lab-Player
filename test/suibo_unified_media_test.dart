import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_sync_merger.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/services/video_source/direct_video_source.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/services/video_source/video_catalog_scope.dart';
import 'package:kazumi/services/danmaku/media_danmaku_service.dart';

void main() {
  test('no live rules/pages, but recorded videos and replays remain', () {
    expect(isLiveOnlyRule('live'), isTrue);
    expect(isLiveOnlyRule('LIVE_STREAM'), isTrue);
    expect(isLiveOnlyRule('anime'), isFalse);
    expect(isKnownLivePage('https://live.bilibili.com/456'), isTrue);
    expect(isKnownLivePage('https://live.douyin.com/1234'), isTrue);
    expect(isKnownLivePage('https://www.bilibili.com/video/BV1MU411S7iJ'),
        isFalse);
    expect(isKnownLivePage('https://example.org/video/直播回放.mp4'), isFalse);
    expect(directVideoFormat('https://live.bilibili.com/video.mp4'), isNull);
  });

  test('Bilibili recorded-video ID resolves independently of content kind', () {
    final video = BilibiliVideoRef.fromUrl(
      'https://www.bilibili.com/video/BV1MU411S7iJ?p=2',
    );
    expect(video?.bvid, 'BV1MU411S7iJ');
    expect(video?.page, 2);
    expect(video?.viewParams['bvid'], 'BV1MU411S7iJ');
    expect(BilibiliVideoRef.fromUrl(
        'https://m.bilibili.com/video/av1234')?.aid, 1234);
    expect(BilibiliVideoRef.fromUrl(
        'https://live.bilibili.com/1234'), isNull);
    expect(BilibiliVideoRef.fromUrl(
        'https://evil-bilibili.com/video/BV1MU411S7iJ'), isNull);
  });

  test('Bilibili native XML comments keep timing, type, color and source', () {
    final entries = MediaDanmakuService.parseBilibiliXml(
      '<i><d p="12.5,1,25,16711680,0,0,0,0">科普&amp;知识</d>'
      '<d p="14,5,25,255,0,0,0,0">置顶</d>'
      '<d p="bad,1,25,0,0,0,0,0">无效</d>'
      '<d p="20,7,25,10,0,0,0,0">不支持的高级弹幕</d></i>',
    );
    expect(entries.length, 2);
    expect(entries[0].message, '科普&知识');
    expect(entries[0].time, 12.5);
    expect(entries[0].type, 1);
    expect(entries[0].source, 'BiliBili');
    expect(entries[1].type, 5);
    expect(MediaDanmakuService.normalizeTitle(' 科 普 '), '科普');
  });

  test('any rule video kind is searchable and collectible without a type gate', () {
    final categories = [
      '动画', '电影', '电视剧', '综艺', '纪录片',
      '短剧', '短视频', '网络节目', '教学视频',
    ];
    for (final category in categories) {
      final item = BangumiItem.fromRule(
        pluginName: 'video-source',
        source: 'https://example.org/video/${Uri.encodeComponent(category)}',
        title: category,
      );
      expect(item.isExternal, isTrue);
      expect(item.type, 0);
      expect(item.nameCn, category);
      expect(item.sourceUrl, isNotEmpty);
    }
  });

  test('on-demand single videos and HLS keep the original video player path', () {
    expect(directVideoFormat('https://example.org/a.MP4?token=abc'),
        VideoSourceFormat.auto);
    expect(directVideoFormat('https://example.org/vod/episode.m3u8?auth=1'),
        VideoSourceFormat.hls);
    expect(directVideoFormat('https://example.org/movie.m4v'),
        VideoSourceFormat.auto);
    expect(directVideoFormat('https://example.org/watch?id=4'), isNull);
    expect(directVideoFormat('https://example.org/video.mpd'), isNull);
    expect(directVideoFormat('file:///private/video.mp4'), isNull);
  });

  test('original anime danmaku timeline and identity remain available', () {
    final anime = BangumiItem.fromJson({
      'id': 12345,
      'type': 2,
      'name': '原版番剧',
      'rating': {'score': 8.0},
    });
    expect(anime.type, 2);
    expect(anime.isExternal, isFalse);
    expect(anime.id, 12345);
    expect(
      DanmakuTimeline.resolveSourceSecond(
        const Duration(seconds: 48),
        3,
      ),
      45,
    );
  });

  test('live-action subjects without ratings or covers remain searchable', () {
    final movie = BangumiItem.fromJson({
      'id': 872345,
      'type': 6,
      'name': '示例电视剧',
      'name_cn': '示例电视剧',
      'summary': '用于解析测试',
      'rating': null,
      'images': null,
    });
    expect(movie.nameCn, '示例电视剧');
    expect(movie.type, 6);
    expect(movie.ratingScore, 0);
    expect(movie.votesCount, isEmpty);
    expect(movie.images, isEmpty);
    expect(movie.isExternal, false);
  });

  test('sparse three-dimensional subjects parse partial rating fields', () {
    final item = BangumiItem.fromJson({
      'id': 827654,
      'type': 6,
      'name': '示例电影',
      'rating': {'score': 7.3},
      'images': {'large': 'https://example.org/movie.jpg', 'grid': null},
    });
    expect(item.rank, 0);
    expect(item.ratingScore, 7.3);
    expect(item.votes, 0);
    expect(item.images['large'], 'https://example.org/movie.jpg');
  });
  test('rule-only media has stable Hive-compatible ID and replay location', () {
    final movie = BangumiItem.fromRule(
      pluginName: 'demo-rule', source: 'https://example.org/movie/1',
      title: '示例电影',
    );
    final repeated = BangumiItem.fromRule(
      pluginName: 'demo-rule', source: 'https://example.org/movie/1',
      title: '示例电影',
    );
    expect(movie.isExternal, isTrue);
    expect(movie.id, repeated.id);
    expect(movie.id, greaterThanOrEqualTo(0x80000000));
    expect(movie.id, lessThanOrEqualTo(0xffffffff));
    expect(movie.sourcePlugin, 'demo-rule');
    expect(movie.sourceUrl, 'https://example.org/movie/1');
    expect(movie.nameCn, '示例电影');
    // Synthetic ID is never a valid Bangumi/DanDanPlay automatic-match ID.
    expect(movie.isExternal, isTrue);
  });

  test('rule-only items stay on local/WebDAV shelf, not Bangumi upload', () {
    final movie = BangumiItem.fromRule(
      pluginName: 'demo-rule', source: 'https://example.org/movie/1',
      title: '示例电影',
    );
    final plan = CollectSyncMerger.planBangumi(
      localCollectibles: [
        CollectedBangumi(movie, DateTime(2026), CollectType.watching.value),
      ],
      remoteCollections: const [],
      priority: BangumiSyncPriority.localFirst,
    );
    expect(plan.totalOperations, 0);
    expect(plan.localOnlyUploads, isEmpty);
  });
}
