import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/video_source/default_cms_sources.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
import 'package:kazumi/services/video_source/direct_video_source.dart';
import 'package:kazumi/services/video_source/video_source_format.dart';

void main() {
  test('automatic defaults keep only distinct public HTTPS API entries', () {
    final list = DefaultCmsSources.parse({
      'spider': 'https://evil.example/spider.jar',
      'sites': [
        {
          'type': 1, 'key': 'sample', 'name': '示例点播',
          'api': 'https://video.example/api.php/provide/vod',
          'searchable': 1, 'quickSearch': 1,
        },
        {
          'type': 1, 'key': 'dupe', 'name': '重复',
          'api': 'https://video.example/api.php/provide/vod/',
        },
        {
          'type': 1, 'name': '91麻豆',
          'api': 'https://adult.example/api.php/provide/vod',
        },
        {
          'type': 3, 'name': 'external Spider',
          'api': 'https://spider.example/api.php/provide/vod',
        },
        {
          'type': 1, 'name': 'private',
          'api': 'https://127.0.0.1/api.php/provide/vod',
        },
        {
          'type': 1, 'name': 'unsafe',
          'api': 'http://insecure.example/api.php/provide/vod',
        },
        {
          'type': 1, 'name': 'host password',
          'api': 'https://secret@video.example/api.php/provide/vod',
        },
      ],
    });
    expect(list, hasLength(1));
    expect(list.single.name, startsWith('CMS · '));
    expect(list.single.type, 'video');
    expect(list.single.searchMode, 'api');
    expect(list.single.chapterMode, 'api');
  });

  test('existing engine parses real CMS poster, ID and multi-route episodes', () {
    final rule = DefaultCmsSources.createPlugin(
      name: 'CMS · Test',
      endpoint: 'https://video.example/api.php/provide/vod',
    );
    final parser = ApiRuleStrategy();
    final request = parser.prepareRequest(rule.searchApiConfig.request,
        {'keyword': '亮剑'});
    expect(request.query['wd'], '亮剑');
    final found = parser.parseSearch(jsonEncode({
      'list': [
        {
          'vod_id': 123,
          'vod_name': '亮剑',
          'vod_pic': 'https://image.example/poster.jpg',
        }
      ]
    }), rule.searchApiConfig);
    expect(found.items, hasLength(1));
    expect(found.items.single.src, '123');
    expect(found.items.single.name, '亮剑');
    expect(found.items.single.imageUrl,
        'https://image.example/poster.jpg');
    final chapterRequest = parser.prepareRequest(
        rule.chapterApiConfig.request, {'source': '123'});
    expect(chapterRequest.query['ids'], '123');
    final chapters = parser.parseChapters(jsonEncode({
      'list': [
        {
          'vod_play_from': '线路一' + r'$$$' + '线路二',
          'vod_play_url': '第1集' + r'$' +
              'https://video.example/e1.m3u8#第2集' + r'$' +
              'https://video.example/e2.m3u8' + r'$$$' +
              '全集' + r'$' + 'https://video.example/movie.mp4',
        }
      ]
    }), rule.chapterApiConfig, source: '123',
        baseUrl: rule.baseUrl);
    expect(chapters.roads, hasLength(2));
    expect(chapters.roads.first.identifier, ['第1集', '第2集']);
    expect(chapters.roads.first.data, hasLength(2));
    expect(directVideoFormat(chapters.roads.first.data.first),
        VideoSourceFormat.hls);
  });

  test('only actual HTTPS pictures can become covers', () {
    final rule = DefaultCmsSources.createPlugin(
      name: 'CMS · Test', endpoint: 'https://video.example/api.php/provide/vod');
    final parsed = const ApiRuleStrategy().parseSearch(jsonEncode({
      'list': [
        {
          'vod_id': '9', 'vod_name': 'test',
          'vod_pic': 'http://127.0.0.1/private.jpg',
        }
      ]
    }), rule.searchApiConfig);
    expect(parsed.items.single.imageUrl, isEmpty);
  });
}
