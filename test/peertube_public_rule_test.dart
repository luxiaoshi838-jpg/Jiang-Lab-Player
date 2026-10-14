import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/video_source/direct_video_source.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('packaged public VOD provider uses PeerTube search without secrets',
      () async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/plugins/PeerTubePublic.json'),
    ) as Map<String, dynamic>;
    final plugin = Plugin.fromJson(data);
    expect(plugin.name, 'PeerTube公开点播');
    expect(plugin.searchMode, 'api');
    expect(plugin.chapterMode, 'api');
    final engine = ApiRuleStrategy();
    final request = engine.prepareRequest(
      plugin.searchApiConfig.request,
      {'keyword': '纪录片'},
    );
    expect(request.url, 'https://peertube.tv/api/v1/search/videos');
    expect(request.query['search'], '纪录片');
    expect(request.query['isLive'], false);
    expect(request.headers, isEmpty);
    expect(plugin.searchApiConfig.listPath, r'$.data[*]');
  });

  test('public video search and HLS details reach the existing player path',
      () async {
    final plugin = Plugin.fromJson(jsonDecode(
      await rootBundle.loadString('assets/plugins/PeerTubePublic.json'),
    ) as Map<String, dynamic>);
    const engine = ApiRuleStrategy();
    final search = engine.parseSearch(
      jsonEncode({
        'data': [
          {'name': '公开纪录片 A', 'uuid': 'ab07ca21-382a-4ed3-ad7a-e05134295790'}
        ]
      }),
      plugin.searchApiConfig,
    );
    expect(search.items.single.name, '公开纪录片 A');
    final source = search.items.single.src;
    final detailRequest = engine.prepareRequest(
      plugin.chapterApiConfig.request, {'source': source});
    expect(detailRequest.url, contains('/api/v1/videos/$source'));
    final roads = engine.parseChapters(
      jsonEncode({
        'streamingPlaylists': [
          {
            'type': 1,
            'playlistUrl': 'https://peertube.tv/static/streaming-playlists/hls/test/master.m3u8'
          }
        ]
      }),
      plugin.chapterApiConfig,
      source: source,
      baseUrl: plugin.baseUrl,
    );
    expect(roads.roads, hasLength(1));
    expect(roads.roads.single.data, hasLength(1));
    expect(directVideoFormat(roads.roads.single.data.single),
        VideoSourceFormat.hls);
  });

  test('missing media manifests cannot become fake playable episodes',
      () async {
    final plugin = Plugin.fromJson(jsonDecode(
      await rootBundle.loadString('assets/plugins/PeerTubePublic.json'),
    ) as Map<String, dynamic>);
    const engine = ApiRuleStrategy();
    final roads = engine.parseChapters(
      '{"streamingPlaylists":[]}',
      plugin.chapterApiConfig,
      source: 'example-id',
      baseUrl: plugin.baseUrl,
    );
    expect(roads.roads, isEmpty);
  });
}
