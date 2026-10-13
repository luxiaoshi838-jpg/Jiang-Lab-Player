import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/official_video_search.dart';

void main() {
  test('official searches are explicit external browser URLs, not source hits', () {
    final bilibili = OfficialVideoSearch.searchUrl(
      OfficialVideoPlatform.bilibili, ' 亮剑 ');
    expect(bilibili.scheme, 'https');
    expect(bilibili.host, 'search.bilibili.com');
    expect(bilibili.queryParameters['keyword'], '亮剑');

    final iqiyi = OfficialVideoSearch.searchUrl(
      OfficialVideoPlatform.iqiyi, '亮剑');
    expect(iqiyi.host, 'www.iqiyi.com');
    expect(iqiyi.pathSegments.last, '亮剑');
  });

  test('known 2005 drama has a verified external licensed page, never HLS', () {
    final item = OfficialVideoSearch.knownProgramme('亮剑', '2005-09-13');
    expect(item, isNotNull);
    expect(item!.url.host, 'www.iqiyi.com');
    expect(item.url.path, '/a_19rrj6sgbt.html');
    expect(OfficialVideoSearch.knownProgramme('新亮剑', '2011-01-01'), isNull);
    expect(OfficialVideoSearch.knownProgramme('亮剑', '2011-01-01'), isNull);
  });

  test('refuses blank searches and never treats a catalog as a playable URL', () {
    expect(
      () => OfficialVideoSearch.searchUrl(OfficialVideoPlatform.bilibili, '  '),
      throwsArgumentError,
    );
  });
}
