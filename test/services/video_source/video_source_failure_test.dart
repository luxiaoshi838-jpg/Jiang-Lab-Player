import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/video_source/video_source_failure.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';

void main() {
  test('only accept HTTP(S) URLs from the online stream resolver', () {
    expect(VideoSourceFailure.isOnlineMediaUrl('https://vod.example/video.m3u8'), true);
    expect(VideoSourceFailure.isOnlineMediaUrl('http://vod.example/file.mp4'), true);
    expect(VideoSourceFailure.isOnlineMediaUrl('javascript:alert(1)'), false);
    expect(VideoSourceFailure.isOnlineMediaUrl('blob:https://example.com/x'), false);
    expect(VideoSourceFailure.isOnlineMediaUrl('file:///tmp/episode.mp4'), false);
    expect(VideoSourceFailure.isOnlineMediaUrl('https:///path'), false);
  });

  test('playlist errors distinguish no results, verification and timeouts', () {
    expect(VideoSourceFailure.playlist(const NoResultException('A')), contains('没有找到'));
    expect(VideoSourceFailure.playlist(const CaptchaRequiredException('A')), contains('验证'));
    expect(VideoSourceFailure.playlist(const ChapterErrorException('A')), contains('分集'));
    expect(VideoSourceFailure.playlist(TimeoutException('token=PRIVATE')), contains('超时'));
  });

  test('HTTP authentication rejection is separate from no results', () {
    final dio = DioException(
      requestOptions: RequestOptions(path: 'https://private.example/secret'),
      response: Response(
        requestOptions: RequestOptions(path: 'https://private.example/secret'),
        statusCode: 403,
      ),
    );
    expect(VideoSourceFailure.playlist(dio), contains('拒绝访问'));
    expect(VideoSourceFailure.stream(dio), contains('限制'));
  });

  test('stream errors never echo URL or token', () {
    const secret = 'private-token-123';
    final errors = [
      VideoSourceFailure.stream(const VideoSourceNotFoundException(secret)),
      VideoSourceFailure.stream(Exception(secret)),
      VideoSourceFailure.stream(const VideoSourceTimeoutException(
        Duration(seconds: 15),
      )),
    ];
    for (final description in errors) {
      expect(description, isNot(contains(secret)));
    }
  });
}
