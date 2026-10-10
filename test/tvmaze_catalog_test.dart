import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/tvmaze_catalog_service.dart';

void main() {
  final raw = <String, dynamic>{
    'score': 8.6,
    'show': {
      'id': 82,
      'name': 'Doctor Who',
      'url': 'https://www.tvmaze.com/shows/82/doctor-who',
      'premiered': '2005-03-26',
      'summary': '<p>A <b>science fiction</b> programme.</p>',
      'image': {'medium': 'https://static.tvmaze.com/uploads/images/medium_portrait/1/1.jpg'}
    }
  };

  test('TVmaze keyless results show exact title and credit the source', () {
    final items = TvmazeCatalogService.parseResults([raw], 'doctor who');
    expect(items, hasLength(1));
    expect(items.single.nameCn, 'Doctor Who');
    expect(items.single.summary, contains('TVmaze'));
    expect(items.single.summary, contains('science fiction programme'));
    expect(items.single.sourceUrl, contains('tvmaze.com'));
    expect(items.single.isExternal, isTrue);
  });

  test('fuzzy matches are not automatically substituted', () {
    expect(TvmazeCatalogService.parseResults([raw], 'Doctor Who 2025'),
        isEmpty);
    expect(TvmazeCatalogService.parseResults([raw], '亮剑'), isEmpty);
  });

  test('rejects untrusted URL and malformed providers', () {
    expect(TvmazeCatalogService.parseResults([
      {'show': {
        'id': 1, 'name': 'Doctor Who',
        'url': 'https://evil.example.com/shows/82'
      }}
    ], 'Doctor Who'), isEmpty);
    expect(TvmazeCatalogService.parseResults({'data': []}, 'Doctor Who'),
        isEmpty);
  });
}
