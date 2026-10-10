import 'dart:async';

import 'package:dio/dio.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

/// Plain-language VOD errors. Never display raw media URLs or tokens.
class VideoSourceFailure {
  static bool isOnlineMediaUrl(String source) {
    final uri = Uri.tryParse(source.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _timeout(Object error) =>
      error is TimeoutException ||
      error is DioException &&
          (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.sendTimeout);

  static String playlist(Object error) {
    if (error is CaptchaRequiredException) {
      return '该来源需要网站验证，请验证后重试';
    }
    if (error is NoResultException) {
      return '该来源没有找到播放列表，请选择其他来源';
    }
    if (error is DioException &&
        (error.response?.statusCode == 401 ||
            error.response?.statusCode == 403)) {
      return '来源网站拒绝访问，可能需要登录或完成验证';
    }
    if (_timeout(error)) {
      return '获取播放列表超时，请检查网络或切换来源';
    }
    if (error is ChapterErrorException) {
      return '来源规则未能解析分集，请检查规则更新或切换来源';
    }
    return '无法获取播放列表，请检查规则或选择其他来源';
  }

  static String stream(Object error) {
    if (error is VideoSourceTimeoutException || _timeout(error)) {
      return '视频地址解析超时，请重试或切换来源';
    }
    if (error is VideoSourceNotFoundException) {
      return '未找到可用视频地址，请选择其他来源';
    }
    if (error is DioException &&
        (error.response?.statusCode == 401 ||
            error.response?.statusCode == 403)) {
      return '视频访问受到限制，可能需要登录或授权';
    }
    return '视频地址解析失败；可能需要登录、网站验证，或该格式不受支持';
  }
}
