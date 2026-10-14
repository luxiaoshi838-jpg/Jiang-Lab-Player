import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/video_source/direct_video_source.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';

/// Verify the existing Dart rule parser against the live official PeerTube
/// API through actual search, playlist resolution and HLS HTTP manifest.
///
/// This does not verify decoding, a Windows/Android GUI or copyrighted shows.
class _PublicHttpExecutor implements RuleRequestExecutor {
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    if (request.method != 'GET') {
      throw StateError('Smoke test only permits public GET');
    }
    final uri = Uri.parse(request.url).replace(
      queryParameters: request.query.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
    return _readText(uri);
  }
}

Future<String> _readText(Uri uri) async {
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw StateError('Only HTTPS public videos are tested');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  client.userAgent = 'Suibo-VOD-Smoke/2.3.11';
  try {
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 12));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
    final response =
        await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('HTTP ' + response.statusCode.toString(), uri: uri);
    }
    return await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 12));
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final data = jsonDecode(
    File('assets/plugins/PeerTubePublic.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final plugin = Plugin.fromJson(data);
  final config = RuleExecutionConfig(
    pluginName: plugin.name,
    baseUrl: plugin.baseUrl,
    usePost: plugin.usePost,
    searchMode: plugin.searchMode,
    chapterMode: plugin.chapterMode,
    searchUrl: plugin.searchURL,
    searchList: plugin.searchList,
    searchName: plugin.searchName,
    searchResult: plugin.searchResult,
    chapterRoads: plugin.chapterRoads,
    chapterResult: plugin.chapterResult,
    searchApiConfig: plugin.searchApiConfig,
    chapterApiConfig: plugin.chapterApiConfig,
    antiCrawlerConfig: plugin.antiCrawlerConfig,
  );
  final engine = RuleEngine(
    requestExecutor: _PublicHttpExecutor(),
    logFailures: false,
  );
  final search = await engine.search(config, 'linux');
  if (search.response.data.isEmpty) {
    throw StateError('The actual Dart rule search returned zero videos');
  }
  for (final video in search.response.data.take(12)) {
    try {
      final chapters = await engine.queryChapters(config, video.src);
      for (final road in chapters.roads) {
        for (final url in road.data) {
          if (directVideoFormat(url) != VideoSourceFormat.hls) continue;
          if (Uri.parse(url).scheme != 'https') continue;
          final contents = await _readText(Uri.parse(url));
          if (!contents.trimLeft().startsWith('#EXTM3U')) continue;
          stdout.writeln('PASS real Suibo rule search / chapters / HLS');
          stdout.writeln('Title: ' + video.name);
          stdout.writeln('HLS host: ' + Uri.parse(url).host);
          return;
        }
      }
    } catch (error) {
      stderr.writeln('Unavailable public sample: ' +
          error.runtimeType.toString());
    }
  }
  throw StateError('No playable HLS manifest from actual source results');
}
