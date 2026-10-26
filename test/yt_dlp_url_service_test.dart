import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/yt_dlp_url_service.dart';

void main() {
  test('accepts public video webpages', () {
    expect(YtDlpUrlService.validate(
      'https://www.bilibili.com/video/BV1test',
    ).host, 'www.bilibili.com');
  });

  test('rejects local and unsupported URLs', () {
    for (final input in [
      'file:///etc/passwd', 'https://localhost/test',
      'http://127.0.0.1:8000/', 'http://10.0.0.2/',
      'http://192.168.0.1/', 'https://user:pass@example.com/',
      'http://[::1]/',
    ]) {
      expect(() => YtDlpUrlService.validate(input),
          throwsA(isA<YtDlpUrlException>()), reason: input);
    }
  });

  test('parses a playable combined stream and request headers', () {
    final item = YtDlpUrlService.fromJson(
      '{"title":"测试视频","url":"https://cdn.example.com/v.m3u8",'
      '"http_headers":{"Referer":"https://example.com/"}}',
    );
    expect(item.title, '测试视频');
    expect(item.url, 'https://cdn.example.com/v.m3u8');
    expect(item.headers['Referer'], 'https://example.com/');
  });

  test('rejects playlists and separate audio/video formats', () {
    expect(
      () => YtDlpUrlService.fromJson('{"entries":[]}'),
      throwsA(isA<YtDlpUrlException>()),
    );
    expect(
      () => YtDlpUrlService.fromJson(
        '{"url":"https://cdn.example.com/v.mp4","requested_formats":[{}]}',
      ),
      throwsA(isA<YtDlpUrlException>()),
    );
  });

  test('rejects local or missing media URLs', () {
    for (final raw in ['{"url":"file:///etc/passwd"}','{}','bad-json']) {
      expect(
        () => YtDlpUrlService.fromJson(raw),
        throwsA(isA<YtDlpUrlException>()),
      );
    }
  });
}
