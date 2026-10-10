import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/tmdb_catalog_service.dart';

void main() {
  final sample = <String, dynamic>{
    'results': [
      {
        'id': 41001, 'media_type': 'tv',
        'name': '一饭封神', 'original_name': '一饭封神',
        'first_air_date': '2025-07-17',
        'overview': '厨艺竞技节目',
        'poster_path': '/poster123.jpg', 'vote_average': 7.4,
      },
      {
        'id': 41002, 'media_type': 'tv',
        'name': '亮剑', 'original_name': '亮剑',
        'first_air_date': '2005-09-12',
        'poster_path': '/drama.jpg',
      },
      {
        'id': 41003, 'media_type': 'tv',
        'name': '大明王朝1566', 'original_name': '大明王朝1566',
        'first_air_date': '2007-01-08',
      },
      {
        'id': 41004, 'media_type': 'person',
        'name': '一饭封神 嘉宾',
      },
      {
        'id': 41005, 'media_type': 'tv',
        'name': '直播间', 'adult': true,
      },
    ],
  };

  test('TMDB parses all three genres using one TV metadata entry model', () {
    final items = TmdbCatalogService.parseSearchResults(sample);
    expect(items.length, 3);
    expect(items.map((i) => i.nameCn).toList(),
        ['一饭封神', '亮剑', '大明王朝1566']);
    expect(items.every((i) => i.sourcePlugin == 'TMDB'), isTrue);
    expect(items.first.images['large'],
        'https://image.tmdb.org/t/p/w500/poster123.jpg');
    expect(items.first.summary, '厨艺竞技节目');
    expect(TmdbCatalogService.tmdbIdFromItem(items.first), 41001);
  });

  test('movie IDs work independently and neither fake rules nor live IDs map', () {
    final movies = TmdbCatalogService.parseSearchResults({
      'results': [
        {'id': 97, 'media_type': 'movie', 'title': '电影作品',
         'original_title': 'Movie Title'},
        {'id': 98, 'media_type': 'unknown', 'title': '不明项目'},
      ]
    });
    expect(movies.length, 1);
    expect(TmdbCatalogService.tmdbIdFromItem(movies.single), 97);
    expect(TmdbCatalogService.parseSearchResults({'results': []}), isEmpty);
  });

  test('duplicate IDs and incomplete records do not create bogus entries', () {
    expect(TmdbCatalogService.parseSearchResults({
      'results': [
        {'id': 100, 'media_type': 'tv', 'name': '节目'},
        {'id': 100, 'media_type': 'tv', 'name': '节目'},
        {'id': 200, 'media_type': 'tv', 'name': ''},
        {'id': null, 'media_type': 'movie', 'title': '电影'},
      ]
    }).length, 1);
  });
}
