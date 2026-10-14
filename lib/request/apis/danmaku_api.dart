import 'package:kazumi/modules/danmaku/danmaku_ch_convert.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';

class DanmakuApi {
  static final DanmakuClient _client = DanmakuClient.instance;

  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    final path = ApiEndpoints.formatUrl(
      ApiEndpoints.dandanAPIInfoByBgmBangumiId,
      [bgmBangumiID],
    );
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData).bangumiId;
  }

  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
    int bangumiID, {
    bool preferCompatible = false,
    bool strictProvider = false,
  }) async {
    final path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    final endPoint = ApiEndpoints.dandanAPIDomain + path;
    final jsonData = await _client.get(
      endPoint,
      preferCompatible: preferCompatible,
      officialOnly: strictProvider && !preferCompatible,
    );
    return DanmakuEpisodeResponse.fromJson(jsonData);
  }

  // Manual title search first uses Kazumi's official provider, and falls
  // back to a configured compatible provider. IDs are tagged with their
  // source so subsequent details/comments stay on that same service.
  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    if (!DanmakuClient.hasOfficialCredentials &&
        !DanmakuClient.hasCompatibleProvider) {
      throw const DanmakuProviderUnavailable();
    }
    final url =
        ApiEndpoints.dandanAPIDomain + ApiEndpoints.dandanAPISearchEpisodes;
    Object? lastFailure;
    final combined = <DanmakuSearchAnime>[];
    bool completedSearch = false;

    void collect(DanmakuSearchResponse result) {
      // Truncated matches are insufficient for safe automatic identity.
      if (result.hasMore) return;
      completedSearch = true;
      combined.addAll(result.animes);
    }

    if (DanmakuClient.hasOfficialCredentials) {
      try {
        final data = await _client.get(
          url,
          queryParameters: {'anime': title, 'v2': 'true'},
          officialOnly: true,
        );
        collect(DanmakuSearchResponse.fromJson(data));
      } catch (error) {
        lastFailure = error;
      }
    }
    if (DanmakuClient.hasCompatibleProvider) {
      // Do not return an official anime result before looking in the
      // compatible catalog. A drama with the same title can exist in both.
      bool compatibleFound = false;
      try {
        final data = await _client.get(
          url,
          queryParameters: {'anime': title, 'v2': 'true'},
          preferCompatible: true,
        );
        final result = DanmakuSearchResponse.fromJson(
          data, compatibleProvider: true,
        );
        collect(result);
        compatibleFound = result.animes.isNotEmpty && !result.hasMore;
      } catch (error) {
        lastFailure = error;
      }
      if (!compatibleFound) {
        try {
          final data = await _client.searchCompatibleTitles(title);
          collect(DanmakuSearchResponse.fromJson(
            data, compatibleProvider: true,
          ));
        } catch (error) {
          lastFailure ??= error;
        }
      }
    }
    if (completedSearch) {
      return DanmakuSearchResponse(animes: combined, hasMore: false);
    }
    throw lastFailure ?? StateError('弹幕搜索服务未返回有效结果');
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
    int bangumiID,
    int episode,
  ) async {
    if (bangumiID == 0) {
      return [];
    }
    // Automatic matching relies on an undocumented episode ID convention.
    return _getComments('$bangumiID${episode.toString().padLeft(4, '0')}');
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(
    int episodeID, {
    bool preferCompatible = false,
    bool strictProvider = false,
  }) => _getComments(
    episodeID.toString(),
    preferCompatible: preferCompatible,
    strictProvider: strictProvider,
  );

  static Future<List<DanmakuEntry>> _getComments(
    String episodeID, {
    bool preferCompatible = false,
    bool strictProvider = false,
  }) async {
    final endPoint =
        '${ApiEndpoints.dandanAPIDomain}${ApiEndpoints.dandanAPIComment}$episodeID';
    final conversion = DanmakuChConvert.fromValue(
      GStorage.getSetting(SettingsKeys.danmakuChConvert),
    );
    KazumiLogger().i('Danmaku: final request URL $endPoint');
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {
        'withRelated': 'true',
        'chConvert': conversion.value.toString(),
      },
      preferCompatible: preferCompatible,
      officialOnly: strictProvider && !preferCompatible,
    );
    final List<dynamic> comments = jsonData['comments'];
    return [for (final comment in comments) DanmakuEntry.fromJson(comment)];
  }
}
