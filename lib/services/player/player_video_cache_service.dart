import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// An isolated mpv demuxer temp directory, never general application temp.
/// Only clear our own files while no owned mpv Player is alive.
class PlayerVideoCacheService {
  PlayerVideoCacheService._();
  static const folderName = 'suibo-mpv-cache';
  static int _active = 0;
  static Future<void>? _clearing;

  static void markOpened() => _active++;
  static void markClosed() {
    if (_active > 0) _active--;
  }

  static Future<Directory> _directory() async {
    final temp = await getTemporaryDirectory();
    final directory = Directory(path.join(temp.path, folderName));
    await directory.create(recursive: true);
    return directory;
  }

  static Future<String> directoryPath() async => (await _directory()).path;

  static Future<void> prepare() async {
    await _clearing;
    if (_active > 0) return;
    final directory = await _directory();
    final threshold = DateTime.now().subtract(const Duration(days: 7));
    await for (final entry in directory.list(followLinks: false)) {
      if (_active > 0) return;
      if (entry is! File) continue;
      try {
        if ((await entry.lastModified()).isBefore(threshold)) {
          await entry.delete();
        }
      } catch (_) {
        // Old-file cleanup never blocks playback.
      }
    }
  }

  static Future<int> size() async {
    final directory = await _directory();
    var bytes = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      try {
        bytes += await entry.length();
      } catch (_) {}
    }
    return bytes;
  }

  static Future<bool> clearIfIdle() async {
    if (_active > 0 || _clearing != null) return false;
    final task = _clearFiles();
    _clearing = task;
    try {
      await task;
      return true;
    } finally {
      _clearing = null;
    }
  }

  static Future<void> _clearFiles() async {
    final directory = await _directory();
    await for (final entry in directory.list(followLinks: false)) {
      if (_active > 0) return;
      if (entry is File) await entry.delete();
    }
  }
}
