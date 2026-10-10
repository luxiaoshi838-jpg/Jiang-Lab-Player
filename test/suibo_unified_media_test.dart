import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_sync_merger.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/services/video_source/direct_video_source.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';

void main() {
  test('any rule video kind is searchable and collectible without a type gate', () {
    final categories = [
      '动画', '电影', '电视剧', '综艺', '纪录片',
      '短剧', '短视频', '网络节目', '教学视频', '直播',
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

  test('direct single videos and live HLS keep the original video player path', () {
    expect(directVideoFormat('https://example.org/a.MP4?token=abc'),
        VideoSourceFormat.auto);
    expect(directVideoFormat('https://example.org/live/room.m3u8?auth=1'),
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
