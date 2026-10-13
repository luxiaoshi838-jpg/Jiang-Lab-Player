import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/video_source/default_cms_sources.dart';
import 'package:kazumi/services/video_source/media_work_index.dart';
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
  throw StateError('No default CMS source returned exact 亮剑 with real poster, episodes and HLS');
}

/// Confirm that the cover actually serves image bytes, not just a URL.
Future<bool> _validPoster(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
      uri.host.isEmpty) {
    return false;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.acceptHeader, 'image/*');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && response.statusCode != 206) {
      return false;
    }
    if (response.headers.contentType?.primaryType != 'image') {
      return false;
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk.take(16 - bytes.length));
      if (bytes.length >= 16) break;
    }
    final jpeg = bytes.length >= 3 &&
        bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final png = bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4e && bytes[3] == 0x47;
    final webp = bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 &&
        bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 &&
        bytes[10] == 0x42 && bytes[11] == 0x50;
    final gif = bytes.length >= 6 &&
        bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    return jpeg || png || webp || gif;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
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
  final exact = search.response.data.where((video) =>
      MediaWorkIndex.normalizedWorkTitle(video.name) == '亮剑').toList();
  if (exact.isEmpty) {
    stdout.writeln('CMS: no exact 亮剑 title among ' +
        search.response.data.length.toString() + ' search results');
    return false;
  }
  for (final video in exact.where((item) => item.imageUrl.isNotEmpty).take(3)) {
    if (!await _validPoster(video.imageUrl)) {
      stderr.writeln('CMS poster failed image-byte verification');
      continue;
    }
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
