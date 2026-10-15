import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Source health is local-only, aggregated by rule name; never persist
/// requested URLs, credentials or media titles in diagnostic records.
class SourceHealthService extends ChangeNotifier {
  SourceHealthService._();
  static final SourceHealthService instance = SourceHealthService._();

  static const _storageKey = 'suiboSourceHealthV1';
  static const _manualKey = 'suiboManualSourceV1';
  static const _maxSources = 160;
  final Map<String, _SourceMetrics> _sources = {};
  final Map<String, String> _manual = {};
  Future<void> _pendingSave = Future<void>.value();
  bool _loaded = false;

  void _load() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = GStorage.getStringListSettingByName(_storageKey);
      for (final value in raw.take(_maxSources)) {
        final map = jsonDecode(value);
        if (map is! Map<String, dynamic>) continue;
        final name = map['n'];
        if (name is! String || name.isEmpty) continue;
        _sources[name] = _SourceMetrics.fromJson(map);
      }
      for (final value in GStorage.getStringListSettingByName(_manualKey)) {
        final idx = value.indexOf(':');
        if (idx <= 0) continue;
        final workId = value.substring(0, idx);
        final plugin = value.substring(idx + 1);
        if (plugin.isNotEmpty) _manual[workId] = plugin;
      }
    } catch (error) {
      KazumiLogger().w('SourceHealthService: local health record unavailable', error: error);
    }
  }

  _SourceMetrics _of(String plugin) {
    _load();
    return _sources.putIfAbsent(plugin, _SourceMetrics.new);
  }

  void recordSearch(String plugin, {required bool success, Duration? latency}) {
    final r = _of(plugin);
    r.searches += 1;
    if (success) r.searchHits += 1;
    _notifyAndSave();
  }

  void recordPlaylist(String plugin, {required bool success, Duration? latency}) {
    final r = _of(plugin);
    r.playlists += 1;
    if (success) r.playlistHits += 1;
    _notifyAndSave();
  }

  void recordPlaybackStart(String plugin, Duration firstFrame) {
    if (plugin.isEmpty) return;
    final r = _of(plugin);
    r.starts += 1;
    r.firstFrameMs = r.firstFrameMs == 0
        ? firstFrame.inMilliseconds.toDouble()
        : r.firstFrameMs * 0.75 + firstFrame.inMilliseconds * 0.25;
    r.lastFailureMs = 0;
    _notifyAndSave();
  }

  void recordBuffering(String plugin, Duration duration) {
    if (plugin.isEmpty || duration < const Duration(milliseconds: 500)) return;
    final r = _of(plugin);
    r.buffers += 1;
    r.bufferMs += duration.inMilliseconds;
    _notifyAndSave();
  }

  void recordFailure(String plugin) {
    if (plugin.isEmpty) return;
    final r = _of(plugin);
    r.failures += 1;
    r.lastFailureMs = DateTime.now().millisecondsSinceEpoch;
    _notifyAndSave();
  }

  void preferManual(int workId, String plugin) {
    if (plugin.isEmpty) return;
    _load();
    _manual[workId.toString()] = plugin;
    _notifyAndSave();
  }

  bool isCoolingDown(String plugin) {
    final r = _of(plugin);
    return r.failures >= 3 &&
        r.lastFailureMs > 0 &&
        DateTime.now().millisecondsSinceEpoch - r.lastFailureMs <
            const Duration(minutes: 10).inMilliseconds;
  }

  /// Neutral for new sources; source quality never depends on rule install order.
  double score(String plugin) {
    final r = _of(plugin);
    final observations = r.starts + r.failures;
    if (observations == 0) {
      return 0.5 + (r.playlists == 0 ? 0 :
          0.05 * (r.playlistHits / r.playlists - 0.5));
    }
    final reliability = (r.starts + 2) / (observations + 4);
    final startupPenalty = r.firstFrameMs > 0
        ? (r.firstFrameMs / 20000).clamp(0.0, 0.25) : 0.0;
    final bufferPenalty = (r.buffers / (r.starts + 2) / 10).clamp(0.0, 0.2);
    return reliability - startupPenalty - bufferPenalty -
        (isCoolingDown(plugin) ? 0.25 : 0.0);
  }

  int compare(String left, String right, {required int workId}) {
    _load();
    final preferred = _manual[workId.toString()];
    if (preferred == left && preferred != right) return -1;
    if (preferred == right && preferred != left) return 1;
    final difference = score(right).compareTo(score(left));
    return difference != 0 ? difference : left.compareTo(right);
  }

  String label(String plugin) {
    final r = _of(plugin);
    if (isCoolingDown(plugin)) return '暂时不可用';
    if (r.starts + r.failures < 3) return '尚未测试';
    if (r.firstFrameMs > 8000 || r.buffers >= r.starts * 3) return '较慢';
    if (r.starts >= 2 && r.starts >= r.failures * 3) return '稳定';
    return '尚未测试';
  }

  void _notifyAndSave() {
    notifyListeners();
    _pendingSave = _pendingSave.then((_) async {
      try {
        final entries = _sources.entries.toList()
          ..sort((a, b) => b.value.lastActivity.compareTo(a.value.lastActivity));
        await GStorage.putStringListSettingByName(_storageKey,
            entries.take(_maxSources).map((e) => jsonEncode(
                <String, dynamic>{'n': e.key, ...e.value.toJson()})).toList());
        await GStorage.putStringListSettingByName(_manualKey,
            _manual.entries.take(200).map((e) => '${e.key}:${e.value}').toList());
      } catch (error) {
        KazumiLogger().w('SourceHealthService: cannot persist local metrics', error: error);
      }
    });
  }
}

class _SourceMetrics {
  _SourceMetrics();
  int searches = 0, searchHits = 0, playlists = 0, playlistHits = 0;
  int starts = 0, failures = 0, buffers = 0, bufferMs = 0;
  int lastFailureMs = 0;
  double firstFrameMs = 0;
  int get lastActivity => lastFailureMs;

  factory _SourceMetrics.fromJson(Map<String, dynamic> raw) {
    final value = _SourceMetrics();
    int readInt(String key) => (raw[key] is num) ? (raw[key] as num).toInt().clamp(0, 10000000000000) : 0;
    value.searches = readInt('s');
    value.searchHits = readInt('sh');
    value.playlists = readInt('p');
    value.playlistHits = readInt('ph');
    value.starts = readInt('st');
    value.failures = readInt('f');
    value.buffers = readInt('b');
    value.bufferMs = readInt('bm');
    value.lastFailureMs = readInt('lf');
    value.firstFrameMs = (raw['ff'] is num) ? (raw['ff'] as num).toDouble().clamp(0.0, 1e8) : 0;
    return value;
  }

  Map<String, dynamic> toJson() => {
    's': searches, 'sh': searchHits, 'p': playlists,
    'ph': playlistHits, 'st': starts, 'f': failures,
    'b': buffers, 'bm': bufferMs, 'lf': lastFailureMs,
    'ff': firstFrameMs,
  };
}
