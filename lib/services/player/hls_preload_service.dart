import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/video_source/direct_video_source.dart';
import 'package:kazumi/services/video_source/services.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';
import 'package:kazumi/services/video_source/video_source_failure.dart';

class PreparedHlsEpisode {
  const PreparedHlsEpisode(this.pageUrl, this.mediaUrl, this.preparedAt);
  final String pageUrl;
  final String mediaUrl;
  final DateTime preparedAt;

  bool validFor(String pageUrl) =>
      this.pageUrl == pageUrl &&
      DateTime.now().difference(preparedAt) < const Duration(seconds: 90);
}

/// Mpv owns current-episode segment readahead. This service NEVER downloads
/// video segments: a shared mpv-compatible HTTP segment cache is not verified.
class HlsPreloadService {
  int _generation = 0;
  WebViewVideoSourceService? _resolver;
  http.Client? _client;
  PreparedHlsEpisode? _prepared;

  static bool safeManifest(String manifest) {
    final data = manifest.trimLeft();
    return data.startsWith('#EXTM3U') &&
        !data.contains('#EXT-X-KEY:') &&
        !data.contains('#EXT-X-SESSION-KEY:') &&
        !data.contains('#EXT-X-SESSION-DATA:') &&
        !data.toLowerCase().contains('widevine') &&
        !data.toLowerCase().contains('playready');
  }

  void cancel({bool keepPrepared = false}) {
    _generation++;
    _resolver?.cancel();
    _client?.close();
    _client = null;
    if (!keepPrepared) _prepared = null;
  }

  PreparedHlsEpisode? takePrepared(String pageUrl) {
    final value = _prepared;
    _prepared = null;
    return value?.validFor(pageUrl) == true ? value : null;
  }

  Future<void> prepare({
    required String pageUrl,
    required bool useLegacyParser,
    required String userAgent,
    required String referer,
    required bool Function() allowed,
  }) async {
    cancel();
    final ticket = _generation;
    if (!allowed()) return;
    final parsedUrl = Uri.tryParse(pageUrl);
    if (parsedUrl == null || !VideoSourceFailure.isOnlineMediaUrl(pageUrl)) {
      return;
    }
    WebViewVideoSourceService? localResolver;
    try {
      var mediaUrl = pageUrl;
      if (directVideoFormat(pageUrl) != VideoSourceFormat.hls) {
        if (directVideoFormat(pageUrl) != null) return;
        final resolver = WebViewVideoSourceService();
        localResolver = resolver;
        _resolver = resolver;
        final result = await resolver.resolve(pageUrl,
            useLegacyParser: useLegacyParser,
            timeout: const Duration(seconds: 10));
        if (ticket != _generation || !allowed()) return;
        mediaUrl = result.url;
      }
      if (directVideoFormat(mediaUrl) != VideoSourceFormat.hls ||
          !VideoSourceFailure.isOnlineMediaUrl(mediaUrl) ||
          !allowed() || ticket != _generation) {
        return;
      }

      final client = http.Client();
      _client = client;
      final request = http.Request('GET', Uri.parse(mediaUrl));
      if (userAgent.isNotEmpty) request.headers['user-agent'] = userAgent;
      if (referer.isNotEmpty) request.headers['referer'] = referer;
      final response = await client.send(request).timeout(
          const Duration(seconds: 8));
      if (response.statusCode != 200 || ticket != _generation ||
          !allowed()) {
        return;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (ticket != _generation || !allowed()) return;
        if (bytes.length + chunk.length > 256 * 1024) return;
        bytes.add(chunk);
      }
      if (!safeManifest(utf8.decode(bytes.takeBytes(), allowMalformed: true))) {
        return;
      }
      if (ticket != _generation || !allowed()) return;
      _prepared = PreparedHlsEpisode(pageUrl, mediaUrl, DateTime.now());
      KazumiLogger().i('HlsPreloadService: next episode HLS playlist resolved (segments not prefetched)');
    } catch (error) {
      // A preloading error must never affect current playback.
      KazumiLogger().w('HlsPreloadService: pre-resolution unavailable');
    } finally {
      if (identical(_resolver, localResolver)) _resolver = null;
      if (ticket == _generation) {
        _client?.close();
        _client = null;
      }
      await localResolver?.dispose();
    }
  }

  Future<void> dispose() async {
    cancel();
    final resolver = _resolver;
    _resolver = null;
    await resolver?.dispose();
  }
}
