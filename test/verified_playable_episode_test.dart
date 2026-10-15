import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/video/video_controller.dart';

void main() {
  group('Safe episode identity', () {
    test('accepts explicit episodes and periods', () {
      expect(verifiedPlayableEpisodeNumber('第12集'), 12);
      expect(verifiedPlayableEpisodeNumber('第 12 话'), 12);
      expect(verifiedPlayableEpisodeNumber('第3期'), 3);
      expect(verifiedPlayableEpisodeNumber('12'), 12);
      expect(verifiedPlayableEpisodeNumber('EP12'), 12);
    });
    test('rejects dates, ambiguous episodes and vague titles', () {
      expect(verifiedPlayableEpisodeNumber('2026-10-15'), isNull);
      expect(verifiedPlayableEpisodeNumber('第12集 第13集'), isNull);
      expect(verifiedPlayableEpisodeNumber('大结局'), isNull);
      expect(verifiedPlayableEpisodeNumber('2026'), isNull);
    });
  });
}
