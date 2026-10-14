import 'package:kazumi/utils/constants.dart';

/// Homepage sections have independent genre menus and independent catalogues.
/// Bangumi subjects only distinguish anime (2) and live action (6); live
/// action is further separated using its work-kind tags, not a shared top list.
enum HomeMediaCategory {
  anime('番剧', 2, <String>[]),
  movie('电影', 6, <String>['电影']),
  series('电视剧', 6, <String>['电视剧', '国产剧', '连续剧']),
  shortDrama('短剧', 6, <String>['短剧', '微短剧', '网络短剧']),
  variety('综艺', 6, <String>['综艺', '真人秀', '娱乐节目']);

  const HomeMediaCategory(this.label, this.subjectType, this.genreTags);

  final String label;
  final int subjectType;

  /// Alternative work-kind tags; each is tried separately (logical OR).
  /// Work-kind plus an optional subcategory are sent together (logical AND).
  final List<String> genreTags;

  String get popularTitle => '热门$label';

  List<String> get subcategories => switch (this) {
        HomeMediaCategory.anime => defaultAnimeTags,
        HomeMediaCategory.movie => const [
            '剧情', '喜剧', '动作', '爱情', '科幻', '悬疑', '犯罪',
            '惊悚', '恐怖', '奇幻', '冒险', '历史', '战争', '家庭',
          ],
        HomeMediaCategory.series => const [
            '剧情', '搞笑', '都市', '历史', '喜剧', '爱情', '悬疑',
            '古装', '犯罪', '家庭', '职场', '奇幻', '科幻', '武侠',
            '战争', '青春', '校园',
          ],
        HomeMediaCategory.shortDrama => const [
            '剧情', '搞笑', '都市', '爱情', '甜宠', '逆袭', '悬疑',
            '古装', '家庭', '穿越', '重生', '奇幻', '喜剧',
          ],
        HomeMediaCategory.variety => const [
            '真人秀', '音乐', '脱口秀', '竞技', '访谈', '旅行', '美食',
            '文化', '生活', '喜剧', '游戏',
          ],
      };

  bool supportsSubcategory(String tag) =>
      tag.isEmpty || subcategories.contains(tag);

  /// A genre is never queried without its parent work-kind tag.
  List<String> combinedTags(String categoryTag, String subcategory) => [
        if (categoryTag.isNotEmpty) categoryTag,
        if (subcategory.isNotEmpty) subcategory,
      ];

  static const int pageSize = 24;
}
