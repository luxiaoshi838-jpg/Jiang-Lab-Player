/// External official platform searches. These URLs do not claim that a
/// playable video exists, and they are not Kazumi rule search results.
enum OfficialVideoPlatform { bilibili, iqiyi }

class VerifiedOfficialProgramme {
  const VerifiedOfficialProgramme({required this.label, required this.url});
  final String label;
  final Uri url;
}

class OfficialVideoSearch {
  /// A verified *external* programme page, not a free media URL.
  /// Do not confuse the page with a playable HLS stream.
  static VerifiedOfficialProgramme? knownProgramme(String name, String airDate) {
    if (name.trim() == '亮剑' &&
        (airDate.isEmpty || airDate.startsWith('2005'))) {
      return VerifiedOfficialProgramme(
        label: '爱奇艺：《亮剑》正版剧集（站外，可能需要会员）',
        url: Uri.parse('https://www.iqiyi.com/a_19rrj6sgbt.html'),
      );
    }
    return null;
  }

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
