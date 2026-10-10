/// External official platform searches. These URLs do not claim that a
/// playable video exists, and they are not Kazumi rule search results.
enum OfficialVideoPlatform { bilibili, iqiyi }

class OfficialVideoSearch {
  static String label(OfficialVideoPlatform platform) => switch (platform) {
        OfficialVideoPlatform.bilibili => '哔哩哔哩',
        OfficialVideoPlatform.iqiyi => '爱奇艺',
      };

  static Uri searchUrl(OfficialVideoPlatform platform, String keyword) {
    final name = keyword.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(keyword, 'keyword', '搜索词不能为空');
    }
    return switch (platform) {
      OfficialVideoPlatform.bilibili =>
        Uri.https('search.bilibili.com', '/all', {'keyword': name}),
      OfficialVideoPlatform.iqiyi =>
        Uri.https('www.iqiyi.com', '/search/$name'),
    };
  }
}
