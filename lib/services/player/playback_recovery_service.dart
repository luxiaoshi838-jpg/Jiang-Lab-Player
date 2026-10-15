/// Conservative recovery decisions. Errors never trigger endless retries.
enum PlaybackFailure { network, sourceUnavailable, decoder, other }
enum RecoveryAction { retry, switchSource, stop }

class PlaybackRecoveryService {
  static const int maxRetries = 2;
  static const List<Duration> retryDelays = [
    Duration(seconds: 2), Duration(seconds: 5),
  ];

  int _attempts = 0;
  bool _switched = false;
  int _generation = 0;

  int get generation => _generation;
  bool get isRecovering => _attempts > 0;

  void cancel() {
    _generation++;
    _attempts = 0;
    _switched = false;
  }

  PlaybackFailure classify(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('decode') || text.contains('codec') ||
        text.contains('unsupported format') ||
        text.contains('failed to recognize file format')) {
      return PlaybackFailure.decoder;
    }
    if (text.contains('404') || text.contains('403') ||
        text.contains('410') || text.contains('not found') ||
        text.contains('http error 5') ||
        text.contains('failed to open')) {
      return PlaybackFailure.sourceUnavailable;
    }
    if (text.contains('timeout') || text.contains('timed out') ||
        text.contains('unreachable') || text.contains('connection') ||
        text.contains('network') || text.contains('reset by peer') ||
        text.contains('eof') || text.contains('end of file') ||
        text.contains('broken pipe')) {
      return PlaybackFailure.network;
    }
    return PlaybackFailure.other;
  }

  RecoveryAction choose(Object error) {
    switch (classify(error)) {
      case PlaybackFailure.network:
        if (_attempts < maxRetries) {
          _attempts++;
          return RecoveryAction.retry;
        }
        if (!_switched) {
          _switched = true;
          return RecoveryAction.switchSource;
        }
        return RecoveryAction.stop;
      case PlaybackFailure.sourceUnavailable:
        if (!_switched) {
          _switched = true;
          return RecoveryAction.switchSource;
        }
        return RecoveryAction.stop;
      case PlaybackFailure.decoder:
      case PlaybackFailure.other:
        return RecoveryAction.stop;
    }
  }

  Duration get delay => retryDelays[(_attempts - 1).clamp(0, maxRetries - 1)];
}
