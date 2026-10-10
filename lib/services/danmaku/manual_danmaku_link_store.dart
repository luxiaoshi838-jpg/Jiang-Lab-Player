import 'package:kazumi/services/storage/storage.dart';

/// User-confirmed links between a non-anime work's episode and a DanDan
/// episodeId. Stored locally; independent of the chosen video-source rule.
/// The original Bangumi-anime automatic lookup remains unchanged.
class ManualDanmakuLinkStore {
  static String keyFor(int workId) => 'vodDanmakuLinkV1_$workId';

  static Map<int, int> decode(List<String> records) {
    final links = <int, int>{};
    for (final record in records) {
      final fields = record.split(':');
      if (fields.length != 2) continue;
      final episode = int.tryParse(fields[0]);
      final episodeId = int.tryParse(fields[1]);
      if (episode != null && episode > 0 &&
          episodeId != null && episodeId > 0) {
        links[episode] = episodeId;
      }
    }
    return links;
  }

  static List<String> encode(Map<int, int> links) {
    final valid = links.entries
        .where((entry) => entry.key > 0 && entry.value > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return valid
        .map((entry) => '${entry.key}:${entry.value}')
        .toList(growable: false);
  }

  static int? lookup(int workId, int episode) {
    if (workId <= 0 || episode <= 0 ||
        GStorage.getSetting(SettingsKeys.privateMode)) {
      return null;
    }
    return decode(GStorage.getStringListSettingByName(keyFor(workId)))[episode];
  }

  static Future<void> save(int workId, int episode, int episodeId) async {
    if (workId <= 0 || episode <= 0 || episodeId <= 0 ||
        GStorage.getSetting(SettingsKeys.privateMode)) {
      return;
    }
    final links =
        decode(GStorage.getStringListSettingByName(keyFor(workId)));
    links[episode] = episodeId;
    await GStorage.putStringListSettingByName(keyFor(workId), encode(links));
  }

  static Future<void> clear(int workId, int episode) async {
    if (workId <= 0 || episode <= 0 ||
        GStorage.getSetting(SettingsKeys.privateMode)) {
      return;
    }
    final links =
        decode(GStorage.getStringListSettingByName(keyFor(workId)));
    links.remove(episode);
    await GStorage.putStringListSettingByName(keyFor(workId), encode(links));
  }
}
