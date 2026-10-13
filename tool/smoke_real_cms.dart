import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/video_source/default_cms_sources.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/video_source/direct_video_source.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';

/// Diagnostic against auto-discovered Apple CMS V10 feeds, using the same
/// Dart rules and parsers as the installed Windows/Android application.
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
  final candidates = await DefaultCmsSources.fetch();
  if (candidates.isEmpty) {
    throw StateError('Default CMS catalogue produced zero valid HTTPS API rules');
  }
  var checkedSources = 0;
  for (final plugin in candidates) {
    checkedSources++;
    try {
      if (await _checkOne(plugin)) return;
    } catch (error) {
      stderr.writeln('Source ' + checkedSources.toString() +
          ' unavailable: ' + error.runtimeType.toString());
    }
  }
  throw StateError('No default CMS source returned real title, cover and episodes');
}

Future<bool> _checkOne(Plugin plugin) async {
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
  final search = await engine.search(config, '亮剑');
  if (search.response.data.isEmpty) return false;
  for (final video in search.response.data.where((v) =>
      v.name.contains('亮剑') && v.imageUrl.isNotEmpty).take(3)) {
    try {
      final chapters = await engine.queryChapters(config, video.src);
      for (final road in chapters.roads) {
        for (final url in road.data) {
          if (directVideoFormat(url) != VideoSourceFormat.hls) continue;
          if (Uri.parse(url).scheme != 'https') continue;
          // Verify only a short HLS manifest, never download media segments.
          final contents = await _readText(Uri.parse(url));
          if (!contents.trimLeft().startsWith('#EXTM3U')) continue;
          stdout.writeln('PASS: native CMS search -> poster -> episodes -> HLS');
          stdout.writeln('Catalogue title: ' + video.name);
          return true;
        }
      }
    } catch (error) {
      stderr.writeln('Unavailable public sample: ' +
          error.runtimeType.toString());
    }
  }
  return false;
}
