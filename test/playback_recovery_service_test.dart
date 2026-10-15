import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/playback_recovery_service.dart';

void main() {
  group('Suibo bounded recovery', () {
    test('network error retries twice then switches once, never loops', () {
      final recovery = PlaybackRecoveryService();
      expect(recovery.choose('connection timeout'), RecoveryAction.retry);
      expect(recovery.delay, const Duration(seconds: 2));
      expect(recovery.choose('connection reset by peer'), RecoveryAction.retry);
      expect(recovery.delay, const Duration(seconds: 5));
      expect(recovery.choose('connection timeout'), RecoveryAction.switchSource);
      expect(recovery.choose('connection timeout'), RecoveryAction.stop);
      expect(recovery.choose('connection timeout'), RecoveryAction.stop);
    });
    test('decoder and ordinary buffering cannot restart playback', () {
      final recovery = PlaybackRecoveryService();
      expect(recovery.choose('codec decode error'), RecoveryAction.stop);
      expect(recovery.choose('buffering'), RecoveryAction.stop);
      expect(recovery.choose('buffering'), RecoveryAction.stop);
    });
    test('source unavailable only tries a verified switch once', () {
      final recovery = PlaybackRecoveryService();
      expect(recovery.choose('404 not found'), RecoveryAction.switchSource);
      expect(recovery.choose('404 not found'), RecoveryAction.stop);
    });
    test('new manual episode resets old retry budget', () {
      final recovery = PlaybackRecoveryService();
      expect(recovery.choose('network timeout'), RecoveryAction.retry);
      final oldGeneration = recovery.generation;
      recovery.cancel();
      expect(recovery.generation, greaterThan(oldGeneration));
      expect(recovery.choose('network timeout'), RecoveryAction.retry);
      expect(recovery.delay, const Duration(seconds: 2));
    });
  });
}
