import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/search/media_source_candidate.dart';
import 'package:kazumi/utils/date_time.dart';
import 'bangumi_interest.dart';

part 'bangumi_item.g.dart';

@HiveType(typeId: 0)
class BangumiItem {
  @HiveField(0)
  int id;
  @HiveField(1)
  int type;
  @HiveField(2)
  String name;
  @HiveField(3)
  String nameCn;
  @HiveField(4)
  String summary;
  @HiveField(5)
  String airDate;
  @HiveField(6)
  int airWeekday;
  @HiveField(7)
  int rank;
  @HiveField(8)
  Map<String, String> images;
  @HiveField(9, defaultValue: [])
  List<BangumiTag> tags;
  @HiveField(10, defaultValue: [])
  List<String> alias;
  @HiveField(11, defaultValue: 0.0)
  double ratingScore;
  @HiveField(12, defaultValue: 0)
  int votes;
  @HiveField(13, defaultValue: [])
  List<int> votesCount;
  @HiveField(14, defaultValue: '')
  String info;
  // Rule-only media has no Bangumi subject ID. These fields are persisted
  // alongside the existing subject, so collections and histories still work.
  @HiveField(15, defaultValue: '')
  String sourcePlugin;
  @HiveField(16, defaultValue: '')
  String sourceUrl;

  bool get isExternal => sourcePlugin.isNotEmpty && sourceUrl.isNotEmpty;

  /// Search-session-only rule hits. Not stored in Hive; bookmarks continue to
  /// use the original stable Bangumi or single-rule identity.
  final List<MediaSourceCandidate> discoveredSources = [];

  // Calendar metadata is separate from counted user tags and is not persisted.
  final List<String> metaTags;
  BangumiInterest? interest;

  BangumiItem({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.airWeekday,
    required this.rank,
    required this.images,
    required this.tags,
    required this.alias,
    required this.ratingScore,
    required this.votes,
    required this.votesCount,
    required this.info,
    this.sourcePlugin = '',
    this.sourceUrl = '',
    this.metaTags = const [],
    this.interest,
  });

  /// Any video returned by a configured rule, independent of its category.
  /// Reserved high positive IDs avoid collisions with normal Bangumi IDs
  /// and remain compatible with Hive box integer keys.
  factory BangumiItem.fromRule({
    required String pluginName,
    required String source,
    required String title,
    String imageUrl = '',
  }) {
    final key = '$pluginName|$source';
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return BangumiItem(
      id: 0x80000000 | hash,
      type: 0, // Unclassified rule item, not a Bangumi subject type.
      name: title,
      nameCn: title,
      summary: '来源：$pluginName',
      airDate: '',
      airWeekday: 1,
      rank: 0,
      images: {'large': imageUrl, 'common': imageUrl,
        'medium': imageUrl, 'small': imageUrl, 'grid': imageUrl},
      tags: [],
      alias: [],
      ratingScore: 0,
      votes: 0,
      votesCount: [],
      info: '',
      sourcePlugin: pluginName,
      sourceUrl: source,
    );
  }

  factory BangumiItem.fromJson(Map<String, dynamic> json) {
    List<String> parseBangumiAliases(Map<String, dynamic> jsonData) {
      if (jsonData.containsKey('infobox') && jsonData['infobox'] is List) {
        final List<dynamic> infobox = jsonData['infobox'];
        for (var item in infobox) {
          if (item is Map && item['key'] == '别名') {
            // api.bgm.tv /v0 uses `value`; next.bgm.tv /p1 uses `values`
            final dynamic raw = item['values'] ?? item['value'];
            if (raw == null) {
              return [];
            }
            if (raw is List) {
              return raw
                  .map<String>((element) {
                    if (element is Map && element.containsKey('v')) {
                      return element['v'].toString();
                    }
                    return element.toString().trim();
                  })
                  .where((alias) => alias.isNotEmpty)
                  .toList();
            }
            final text = raw.toString().trim();
            return text.isEmpty ? [] : [text];
          }
        }
      }
      return [];
    }

    List<int> parseBangumiVoteCount(Map<String, dynamic> jsonData) {
      final rating = jsonData['rating'];
      if (rating is! Map) return [];
      final json = rating['count'];
      if (json is Map<String, dynamic>) {
        return List<int>.generate(
          10, (i) => (json['${i + 1}'] as num?)?.toInt() ?? 0,
        );
      }
      if (json is List<dynamic>) {
        return json.map((e) => (e as num?)?.toInt() ?? 0).toList();
      }
      return [];
    }

    String resolveAirDateString(Map<String, dynamic> jsonData) {
      String? nonEmpty(dynamic v) {
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }

      final fromTop = nonEmpty(jsonData['date']);
      if (fromTop != null) return fromTop;
      final airtime = jsonData['airtime'];
      if (airtime is Map) {
        final fromAir = nonEmpty(airtime['date']);
        if (fromAir != null) return fromAir;
      }
      return '';
    }

    final String airDateStr = resolveAirDateString(json);
    final rawRating = json['rating'];
    final rating = rawRating is Map ? rawRating : const <String, dynamic>{};
    final rawImages = json['images'];
    final images = <String, String>{};
    if (rawImages is Map) {
      for (final entry in rawImages.entries) {
        if (entry.key is String && entry.value is String) {
          images[entry.key as String] = entry.value as String;
        }
      }
    } else if (json['image'] is String) {
      images['large'] = json['image'] as String;
    }

    final rawTags = json['tags'] as List? ?? [];
    final tagList = rawTags.map((tag) => BangumiTag.fromJson(tag)).toList();
    final rawMetaTags = json['metaTags'];
    BangumiInterest? interest;
    final interestRaw = json['interest'];
    if (interestRaw is Map<String, dynamic>) {
      interest = BangumiInterest.fromJson(interestRaw);
    } else if (interestRaw is Map) {
      interest =
          BangumiInterest.fromJson(Map<String, dynamic>.from(interestRaw));
    }
    return BangumiItem(
      id: json['id'],
      type: json['type'] ?? 2,
      name: json['name'] ?? '',
      nameCn: (json['name_cn'] ?? '') == ''
          ? (((json['nameCN'] ?? '') == '') ? json['name'] : json['nameCN'])
          : json['name_cn'],
      summary: json['summary'] ?? '',
      airDate: airDateStr,
      airWeekday:
          dateStringToWeekday(airDateStr.isEmpty ? '2000-11-11' : airDateStr),
      rank: (rating['rank'] as num?)?.toInt() ?? 0,
      images: images,
      tags: tagList,
      alias: parseBangumiAliases(json),
      ratingScore:
          double.parse(((rating['score'] as num?)?.toDouble() ?? 0)
              .toStringAsFixed(1)),
      votes: (rating['total'] as num?)?.toInt() ?? 0,
      votesCount: parseBangumiVoteCount(json),
      info: json['info'] ?? '',
      metaTags: rawMetaTags is List
          ? rawMetaTags
              .whereType<String>()
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
          : const [],
      interest: interest,
    );
  }
}
