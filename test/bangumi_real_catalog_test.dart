import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/bangumi_real_catalog.dart';

void main() {
  test('Chinese TV-drama search uses only official Bangumi real subjects', () {
    final body = BangumiRealCatalog.searchBody('亮剑');
    expect(body['keyword'], '亮剑');
    expect(body['sort'], 'match');
    expect((body['filter'] as Map)['type'], [6]);
  });

  test('real existing drama keeps cover, rating and first air date', () {
    final result = BangumiRealCatalog.exactItem({
      'data': [
        {
          'id': 127063,
          'type': 6,
          'name': '亮剑',
          'name_cn': '亮剑',
          'date': '2005-09-13',
          'summary': '中国大陆电视剧',
          'images': {
            'large': 'https://lain.bgm.tv/pic/cover/l/example.jpg',
            'common': 'https://lain.bgm.tv/pic/cover/c/example.jpg'
          },
          'rating': {'rank': 172, 'score': 8.2, 'total': 496},
        }
      ]
    }, '亮剑');
    expect(result, isNotNull);
    expect(result!.isExternal, isFalse);
    expect(result.type, 6);
    expect(result.id, 127063);
    expect(result.images['large'], startsWith('https://'));
    expect(result.airDate, '2005-09-13');
    expect(result.ratingScore, 8.2);
  });

  test('misleading other editions and absent poster remain honest', () {
    final data = {'data': [
      {'id': 1, 'type': 6, 'name': '新亮剑', 'images': {}},
    ]};
    expect(BangumiRealCatalog.exactItem(data, '亮剑'), isNull);
    expect(BangumiRealCatalog.exactItem({'data': []}, '亮剑'), isNull);
  });

  test('does not automatically choose between multiple matching editions', () {
    final match = {'name': '亮剑', 'name_cn': '亮剑', 'type': 6};
    expect(BangumiRealCatalog.exactItem({
      'data': [
        {...match, 'id': 1},
        {...match, 'id': 2},
      ]
    }, '亮剑'), isNull);
  });
}
