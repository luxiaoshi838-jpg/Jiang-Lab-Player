/// 首页四类点播内容。所有分类均使用同一热度排序和真实目录数据。
enum HomeMediaCategory {
  anime('番剧', 2, <String>[]),
  movie('电影', 6, <String>['电影']),
  series('电视剧', 6, <String>['电视剧', '连续剧']),
  shortDrama('短剧', 6, <String>['短剧', '微短剧', '网络短剧']);

  const HomeMediaCategory(this.label, this.subjectType, this.genreTags);

  final String label;
  final int subjectType;
  final List<String> genreTags;

  static const int visibleCount = 12;
}
