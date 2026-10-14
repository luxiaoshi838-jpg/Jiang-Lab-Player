import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';

void main() {
  test('danmu_api request keeps its token prefix and official request path', () {
    final official = Uri.parse(
      'https://api.dandanplay.net/api/v2/search/episodes?anime=亮剑');
    final fallback = DanmakuClient.compatibleUri(
      official, 'https://comments.example.com/public-token/');
    expect(fallback, isNotNull);
    expect(fallback!.path, '/public-token/api/v2/search/episodes');
    expect(fallback.queryParameters['anime'], '亮剑');
  });

  test('never send a DanDanPlay signature to unsupported or private hosts', () {
    final official = Uri.parse('https://api.dandanplay.net/api/v2/comment/19');
    expect(DanmakuClient.compatibleUri(official, 'https://api.danmu.icu'), isNull);
    expect(DanmakuClient.compatibleUri(official, 'http://localhost:9321'), isNull);
    expect(DanmakuClient.compatibleUri(official, 'https://api.dandanplay.net'), isNull);
    expect(DanmakuClient.compatibleUri(
      Uri.parse('https://api.dandanplay.net/api/v2/bangumi/bgmtv/4'),
      'https://comments.example.com'), isNull);
    expect(DanmakuClient.compatibleUri(
      Uri.parse('https://other.example.com/api/v2/comment/19'),
      'https://comments.example.com'), isNull);
  });
}
