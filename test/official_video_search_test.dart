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

  test('refuses blank searches and never treats a catalog as a playable URL', () {
    expect(
      () => OfficialVideoSearch.searchUrl(OfficialVideoPlatform.bilibili, '  '),
      throwsArgumentError,
    );
  });
}
