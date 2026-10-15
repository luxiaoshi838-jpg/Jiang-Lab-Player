import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/hls_preload_service.dart';

void main() {
  group('Suibo playlist-only HLS preloading', () {
    test('accepts ordinary clear HLS media playlist', () {
      expect(HlsPreloadService.safeManifest(
          '#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:8.0,\nseg1.ts'),
          isTrue);
    });
    test('rejects encrypted/DRM playlist for speculative preloading', () {
      expect(HlsPreloadService.safeManifest(
          '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"'),
          isFalse);
      expect(HlsPreloadService.safeManifest(
          '#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES'),
          isFalse);
    });
    test('rejects HTML error pages and empty manifest', () {
      expect(HlsPreloadService.safeManifest('<html>error</html>'), isFalse);
      expect(HlsPreloadService.safeManifest(''), isFalse);
    });
    test('prepared URL can only be reused with same page and short TTL', () {
      final item = PreparedHlsEpisode('https://a.test/ep12',
          'https://a.test/ep12.m3u8', DateTime.now());
      expect(item.validFor('https://a.test/ep12'), isTrue);
      expect(item.validFor('https://a.test/ep13'), isFalse);
      final stale = PreparedHlsEpisode('https://a.test/ep12',
          'https://a.test/ep12.m3u8',
          DateTime.now().subtract(const Duration(minutes: 3)));
      expect(stale.validFor('https://a.test/ep12'), isFalse);
    });
  });
}
