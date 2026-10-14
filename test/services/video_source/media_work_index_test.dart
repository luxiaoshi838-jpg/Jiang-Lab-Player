import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/media_source_candidate.dart';
import 'package:kazumi/services/video_source/media_work_index.dart';

void main() {
  BangumiItem subject(String title, int id, {String date = ''}) =>
      BangumiItem.fromJson({
        'id': id,
        'type': 6,
        'name': title,
        'name_cn': title,
        'date': date,
      });

  const first = MediaSourceCandidate(
      pluginName: '资源站A', title: '亮剑', url: 'https://a.example/v/1');
  const second = MediaSourceCandidate(
      pluginName: '资源站B', title: '《亮剑》', url: 'https://b.example/v/2');

  test('anime and live-action 凡人修仙传 retain separate source and poster', () {
    final drama = subject('凡人修仙传', 601);
    drama.images = {'large': 'https://example.org/drama.jpg'};
    final works = <BangumiItem>[drama];
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
      pluginName: '动画规则',
      title: '凡人修仙传',
      url: 'https://anime.example/fanren',
      imageUrl: 'https://anime.example/poster.jpg',
      mediaType: 2,
    ));
    expect(works, hasLength(2));
    expect(drama.discoveredSources, isEmpty);
    final anime = works.singleWhere((w) => w.type == 2);
    expect(anime.images['large'], 'https://anime.example/poster.jpg');
    expect(anime.discoveredSources, hasLength(1));
    MediaWorkIndex.addMetadata(works, subject('凡人修仙传', 602));
    expect(works.singleWhere((w) => w.type == 2).images['large'],
        'https://anime.example/poster.jpg');
    expect(works.where((w) => w.type == 6), hasLength(1));
  });

  test('live-action metadata never replaces same-title anime source shell', () {
    final works = <BangumiItem>[];
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
      pluginName: '动画规则',
      title: '凡人修仙传',
      url: 'https://anime.example/fanren',
      mediaType: 2,
    ));
    MediaWorkIndex.addMetadata(works, subject('凡人修仙传', 701));
    expect(works, hasLength(2));
    expect(works.singleWhere((w) => w.type == 2).discoveredSources,
        hasLength(1));
  });

  test('two source URLs become distinct selectable lines under one work', () {
    final works = <BangumiItem>[subject('亮剑', 127)];
    MediaWorkIndex.addRuleHit(works, first);
    MediaWorkIndex.addRuleHit(works, second);
    MediaWorkIndex.addRuleHit(works, second);
    expect(works, hasLength(1));
    expect(works.single.id, 127);
    expect(works.single.discoveredSources, hasLength(2));
    expect(works.single.discoveredSources.map((s) => s.pluginName),
        ['资源站A', '资源站B']);
  });

  test('rule-only hit is upgraded to metadata while keeping both URLs', () {
    final works = <BangumiItem>[];
    MediaWorkIndex.addRuleHit(works, first);
    MediaWorkIndex.addRuleHit(works, second);
    final catalog = BangumiItem.fromRule(
        pluginName: '百科影视目录',
        source: 'https://zh.wikipedia.org/wiki/亮剑', title: '亮剑');
    MediaWorkIndex.addMetadata(works, catalog);
    expect(works, hasLength(1));
    expect(works.single.sourcePlugin, '百科影视目录');
    expect(works.single.discoveredSources, hasLength(2));
    MediaWorkIndex.addMetadata(works, subject('亮剑', 127));
    expect(works.single.id, 127);
    expect(works.single.isExternal, false);
    expect(works.single.discoveredSources, hasLength(2));
  });

  test('bracketed year result attaches only to compatible catalog edition', () {
    final item = subject('亮剑', 127, date: '2005-09-12');
    final works = <BangumiItem>[item];
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
      pluginName: 'source',
      title: '亮剑（2005）',
      url: 'https://videos.example/lj2005',
    ));
    expect(works, hasLength(1));
    expect(item.discoveredSources, hasLength(1));
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
      pluginName: 'source',
      title: '亮剑（2015）',
      url: 'https://videos.example/lj2015',
    ));
    expect(works, hasLength(2));
    expect(item.discoveredSources, hasLength(1));
  });

  test('names in different seasons are never collapsed', () {
    final works = <BangumiItem>[];
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
        pluginName: 'A', title: '一饭封神 第一季', url: 'https://a.example/s1'));
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
        pluginName: 'A', title: '一饭封神 第二季', url: 'https://a.example/s2'));
    expect(works.length, 2);
    expect(works.every((e) => e.discoveredSources.length == 1), true);
  });

  test('catalog and rule URL must remain separate', () {
    final works = <BangumiItem>[];
    MediaWorkIndex.addMetadata(works, BangumiItem.fromRule(
        pluginName: '百科影视目录',
        source: 'https://zh.wikipedia.org/wiki/一饭封神',
        title: '一饭封神'));
    expect(works.single.discoveredSources, isEmpty);
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
        pluginName: '综艺来源', title: '一饭封神',
        url: 'https://vod.example/variety'));
    expect(works.single.discoveredSources.single.url,
        'https://vod.example/variety');
    expect(works.single.sourceUrl, contains('wikipedia.org'));
  });

  test('ambiguous title with different years does not attach a wrong line', () {
    final works = <BangumiItem>[
      subject('同名影片', 501, date: '2005-02-01'),
      subject('同名影片', 502, date: '2015-02-01'),
    ];
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
        pluginName: 'A', title: '同名影片',
        url: 'https://vod.example/ambiguous'));
    expect(works[0].discoveredSources, isEmpty);
    expect(works[1].discoveredSources, isEmpty);
    expect(works.length, 3);
  });

  test('a title alias can match without mixing unrelated works', () {
    final item = subject('大明王朝1566', 10);
    item.alias.add('大明王朝 1566');
    final works = <BangumiItem>[item];
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
        pluginName: 'A', title: '大明王朝 1566',
        url: 'https://vod.example/history'));
    expect(works, hasLength(1));
    expect(item.discoveredSources, hasLength(1));
    MediaWorkIndex.addRuleHit(works, const MediaSourceCandidate(
        pluginName: 'A', title: '大明王朝1567',
        url: 'https://vod.example/different'));
    expect(works, hasLength(2));
  });
}
