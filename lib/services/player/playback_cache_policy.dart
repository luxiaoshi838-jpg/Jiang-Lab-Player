import 'dart:async';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/player/low_memory_mode.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:media_kit/media_kit.dart';

class PlaybackCachePolicy {
  PlaybackCachePolicy({
    required bool Function() isLocalPlayback,
    required Player? Function() currentPlayer,
  })  : _isLocalPlayback = isLocalPlayback,
        _currentPlayer = currentPlayer;

  // mpv/media_kit uses these values as demuxer packet cache limits, not a
  // traditional HTTP disk cache. The old 2 MiB mobile cap could starve HLS
  // segment playback; the 1500 MiB normal cap caused excessive retention.
  // Keep headroom for mobile and desktop without megabyte-scale stalls.
  static const int lowMemoryBufferSize = 16 * 1024 * 1024;
  static const int defaultBufferSize = 96 * 1024 * 1024;
  static const int maximumBackBufferSize = 24 * 1024 * 1024;

  // Short, bounded forward prefetch. Unlimited (36000s) readahead is both
  // unnecessary and expensive on metered connections.
  static const int networkPrefetchSeconds = 30;
  static const int networkResumeSeconds = 3;

  static int backBufferFor(int forwardSize) {
    final quarter = forwardSize ~/ 4;
    return quarter < maximumBackBufferSize ? quarter : maximumBackBufferSize;
  }

  final bool Function() _isLocalPlayback;
  final Player? Function() _currentPlayer;
  final AsyncSerialQueue _writes = AsyncSerialQueue();

  StreamSubscription<void>? _settingsSubscription;

  bool get networkAutomatic =>
      LowMemoryMode.current == LowMemoryMode.auto &&
      !_isLocalPlayback() &&
      MeteredNetworkService.isMetered;

  int get bufferSize => LowMemoryMode.current.isEnabled(
        isMetered: MeteredNetworkService.isMetered,
        isLocalPlayback: _isLocalPlayback(),
      )
          ? lowMemoryBufferSize
          : defaultBufferSize;

  void startWatching() {
    if (_settingsSubscription != null) {
      return;
    }
    _settingsSubscription = LowMemoryMode.watch().listen((_) => _onChanged());
    MeteredNetworkService.listenable.addListener(_onChanged);
  }

  void stopWatching() {
    MeteredNetworkService.listenable.removeListener(_onChanged);
    unawaited(_settingsSubscription?.cancel());
    _settingsSubscription = null;
  }

  Future<void> apply() async {
    final player = _currentPlayer();
    if (player == null) {
      return;
    }
    try {
      final pp = player.platform as NativePlayer;
      // A stale player's initialization must not block its replacement's writes.
      await pp.waitForPlayerInitialization;
      await _writes.run(() async {
        if (!identical(_currentPlayer(), player)) {
          return;
        }
        final forwardBytes = bufferSize;
        await pp.setProperty('demuxer-max-bytes', forwardBytes.toString());
        if (!identical(_currentPlayer(), player)) return;
        await pp.setProperty(
          'demuxer-max-back-bytes', backBufferFor(forwardBytes).toString());
        if (!identical(_currentPlayer(), player)) return;
        // Preserve local-file performance, apply a separate network policy.
        if (!_isLocalPlayback()) {
          await pp.setProperty(
              'cache-secs', networkPrefetchSeconds.toString());
          if (!identical(_currentPlayer(), player)) return;
          // On an actual underrun, collect a few seconds before resuming to
          // avoid rapid stop/start cycles. Do not delay initial startup.
          await pp.setProperty(
              'cache-pause-wait', networkResumeSeconds.toString());
        }
      });
    } catch (e) {
      KazumiLogger().w(
        'PlaybackCachePolicy: failed to apply demuxer cache size',
        error: e,
      );
    }
  }

  void _onChanged() {
    unawaited(apply());
  }
}
