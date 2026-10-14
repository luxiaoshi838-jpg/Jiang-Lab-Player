import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/playback_cache_policy.dart';

void main() {
  group('Bounded online playback buffering', () {
    test('mobile low-memory mode retains more than one HLS segment', () {
      expect(PlaybackCachePolicy.lowMemoryBufferSize, 16 * 1024 * 1024);
      expect(PlaybackCachePolicy.lowMemoryBufferSize, greaterThan(2 * 1024 * 1024));
    });

    test('normal buffering is bounded and backwards cache is smaller', () {
      expect(PlaybackCachePolicy.defaultBufferSize, 96 * 1024 * 1024);
      expect(PlaybackCachePolicy.defaultBufferSize, lessThan(256 * 1024 * 1024));
      for (final size in <int>[
        PlaybackCachePolicy.lowMemoryBufferSize,
        PlaybackCachePolicy.defaultBufferSize,
      ]) {
        expect(PlaybackCachePolicy.backBufferFor(size), lessThan(size));
        expect(PlaybackCachePolicy.backBufferFor(size),
            lessThanOrEqualTo(PlaybackCachePolicy.maximumBackBufferSize));
      }
    });

    test('network prefetch is finite; stall recovery waits briefly', () {
      expect(PlaybackCachePolicy.networkPrefetchSeconds, inInclusiveRange(10, 60));
      expect(PlaybackCachePolicy.networkResumeSeconds, inInclusiveRange(2, 5));
    });
  });
}
