import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/crypto.dart';

/// A missing provider is not an empty danmaku search result.
class DanmakuProviderUnavailable implements Exception {
  const DanmakuProviderUnavailable();

  @override
  String toString() => '弹幕服务未连接：正式构建缺少有效的弹幕搜索服务。';
}

class DanmakuClient {
  /// Keep the original Kazumi official protocol. A separately configured
  /// compatible API is used only on the same /api/v2/ paths, without any
  /// DanDanPlay credentials or signing headers.
  static Uri? compatibleUri(Uri requested, String configuredBase) {
    if (requested.scheme != 'https' ||
        requested.host != 'api.dandanplay.net' ||
        !requested.path.startsWith('/api/v2/') ||
        requested.path.contains('/bgmtv/')) {
      return null;
    }
    final base = Uri.tryParse(configuredBase.trim());
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.host == 'api.danmu.icu' ||
        base.host == 'api.dandanplay.net') {
      return null;
    }
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$prefix${requested.path}',
      query: requested.query,
    );
  }

  DanmakuClient._();

  static final DanmakuClient instance = DanmakuClient._();

  static const String compatibleBase =
      String.fromEnvironment('SUIBO_DANMU_API_URL',
          defaultValue: 'https://suibo-danmaku.onrender.com');

  static bool get hasOfficialCredentials =>
      (dandanCredentials['id'] ?? '').trim().isNotEmpty &&
      (dandanCredentials['value'] ?? '').trim().isNotEmpty;

  static bool get hasCompatibleProvider =>
      compatibleUri(
        Uri.parse('https://api.dandanplay.net/api/v2/search/episodes'),
        compatibleBase,
      ) != null;

  /// Manual search and automatic matching share one clearly diagnosed
  /// connection. Do not send unsigned requests to official DanDanPlay.
  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
    bool preferCompatible = false,
    bool officialOnly = false,
  }) async {
    if (preferCompatible && officialOnly) {
      throw ArgumentError('Cannot require both danmaku providers');
    }
    final uri = Uri.parse(url);
    final fallback = compatibleUri(uri, compatibleBase);
    if ((preferCompatible && fallback == null) ||
        (officialOnly && !hasOfficialCredentials) ||
        (!hasOfficialCredentials && fallback == null)) {
      throw const DanmakuProviderUnavailable();
    }

    Future<dynamic> request(Uri target, {required bool official}) async {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final requestHeaders = official
          ? <String, dynamic>{
              'user-agent': getRandomUA(),
              'referer': '',
              'X-Auth': 1,
              'X-AppId': dandanCredentials['id'],
              'X-Timestamp': timestamp,
              'X-Signature': generateDandanSignature(uri.path, timestamp),
              ...headers,
            }
          : <String, dynamic>{'user-agent': getRandomUA()};
      final response = await DioFactory.apiDio.get(
        target.toString(),
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      return response.data;
    }

    try {
      if (preferCompatible || !hasOfficialCredentials) {
        return await request(fallback!, official: false);
      }
      try {
        return await request(uri, official: true);
      } on DioException catch (error) {
        // A genuine alternative service may keep search working even when
        // the original service is unreachable or rejects a revoked key.
        // Never forward X-AppId/X-Signature to that service.
        if (officialOnly ||
            fallback == null ||
            (error.response != null &&
                error.response!.statusCode != 401 &&
                error.response!.statusCode != 403 &&
                error.response!.statusCode != 429 &&
                error.response!.statusCode! < 500)) {
          rethrow;
        }
        return await request(fallback, official: false);
      }
    } on DioException catch (error) {
      throw await NetworkErrorMapper.mapException(error);
    }
  }

  /// Companion lookup for danmu_api implementations that expose work-title
  /// search as /api/v2/search/anime?keyword=. Not an official API endpoint.
  Future<dynamic> searchCompatibleTitles(String keyword) async {
    final requested = Uri.parse(
        'https://api.dandanplay.net/api/v2/search/anime');
    final fallback = compatibleUri(requested, compatibleBase);
    if (fallback == null) {
      throw const DanmakuProviderUnavailable();
    }
    try {
      final response = await DioFactory.apiDio.get(
        fallback.toString(),
        queryParameters: {'keyword': keyword},
        options: Options(headers: {'user-agent': getRandomUA()}),
      );
      return response.data;
    } on DioException catch (error) {
      throw await NetworkErrorMapper.mapException(error);
    }
  }
}
