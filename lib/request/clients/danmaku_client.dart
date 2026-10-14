import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/crypto.dart';

class DanmakuClient {
  /// danmu_api implements these DanDanPlay-compatible endpoints. Preserve
  /// its optional /TOKEN path prefix and never send signature credentials to
  /// another host. The XML-only danmu.icu endpoint is NOT compatible.
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

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uri = Uri.parse(url);
    // Original Kazumi authentication takes priority whenever configured.
    // When its credentials are unavailable, use the developer-provisioned
    // danmu_api-compatible service without sending an invalid X-Signature.
    const compatibleBase = String.fromEnvironment('SUIBO_DANMU_API_URL');
    final hasOfficialCredentials =
        (dandanCredentials['id'] ?? '').isNotEmpty &&
        (dandanCredentials['value'] ?? '').isNotEmpty;
    final fallback = hasOfficialCredentials
        ? null
        : compatibleUri(uri, compatibleBase);
    final requestHeaders = fallback == null
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

    try {
      final response = await DioFactory.apiDio.get(
        fallback?.toString() ?? url,
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}
