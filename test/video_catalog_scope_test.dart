import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/video_catalog_scope.dart';

void main() {
  test('real drama searches public video and multi-category rules, not Kazumi anime sites', () {
    expect(isConfirmedDramaCatalogue(6, ''), isTrue);
    expect(isConfirmedDramaCatalogue(0, '百科影视目录'), isTrue);
    expect(isConfirmedDramaCatalogue(0, 'TVmaze节目目录'), isTrue);
    expect(isConfirmedDramaCatalogue(2, ''), isFalse);
    expect(isRelevantRuleTypeForDrama('anime'), isFalse);
    expect(isRelevantRuleTypeForDrama('  ANIME '), isFalse);
    for (final type in ['video', 'tv', 'movie', 'documentary', 'all', 'other']) {
      expect(isRelevantRuleTypeForDrama(type), isTrue, reason: type);
    }
    expect(isLiveOnlyRule('live'), isTrue);
    expect(isLiveOnlyRule('video'), isFalse);
  });
}
