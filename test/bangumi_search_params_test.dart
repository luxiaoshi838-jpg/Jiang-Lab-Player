import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/utils/search_parser.dart';

void main() {
  group('BangumiApi.buildBangumiSearchParams', () {
    test('keeps default search params compatible', () {
      final params = BangumiApi.buildBangumiSearchParams('frieren');
      final filter = params['filter'] as Map<String, dynamic>;

      expect(params['keyword'], 'frieren');
      expect(params['sort'], 'heat');
      expect(filter['type'], [2, 6]);
      expect(filter.containsKey('tag'), isFalse);
      expect(filter.containsKey('rank'), isFalse);
      expect(filter['nsfw'], isFalse);
    });

    test('Chinese dramas and shows are not filtered by rank', () {
      for (final title in ['亮剑', '一饭封神', '大明王朝1566']) {
        final filter = BangumiApi.buildBangumiSearchParams(title)['filter']
            as Map<String, dynamic>;
        expect(filter['type'], [2, 6]);
        expect(filter.containsKey('rank'), isFalse);
      }
    });
    test('explicit rank sorting keeps the rank restriction', () {
      final filter = BangumiApi.buildBangumiSearchParams(
          '亮剑', sort: 'rank')['filter'] as Map<String, dynamic>;
      expect(filter['rank'], [">0", "<=99999"]);
    });
    test('builds advanced filter params', () {
      final params = BangumiApi.buildBangumiSearchParams(
        'bocchi',
        tags: ['音乐', '漫画改'],
        sort: 'score',
        dateRange: const SearchDateRange(
          start: '2022-09-01',
          end: '2022-12-01',
        ),
        rankRange: const SearchIntRange(min: 1, max: 1000),
        scoreRange: const SearchDoubleRange(min: 8.0, max: 10.0),
        weekdays: const [6, 1],
      );
      final filter = params['filter'] as Map<String, dynamic>;

      expect(params['keyword'], 'bocchi');
      expect(params['sort'], 'score');
      expect(filter['tag'], ['音乐', '漫画改']);
      expect(filter['air_date'], [">=2022-09-01", "<2022-12-01"]);
      expect(filter['rank'], [">=1", "<=1000"]);
      expect(filter['rating'], [">=8.0", "<=10.0"]);
      expect(filter['air_weekday'], [1, 6]);
      expect(filter['nsfw'], isFalse);
    });
  });
}
