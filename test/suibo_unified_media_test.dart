import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/sync_priority.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_sync_merger.dart';
import 'package:kazumi/modules/collect/collect_type.dart';

void main() {
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
