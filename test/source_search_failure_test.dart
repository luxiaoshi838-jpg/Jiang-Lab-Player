import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

void main() {
  test('403 blocked search cannot masquerade as no matching episode', () {
    final error = SearchErrorException('source', cause: NetworkException(
      type: NetworkExceptionType.badResponse,
      message: 'redacted',
      statusCode: 403,
    ));
    expect(sourceSearchFailureHint(error), contains('拒绝访问'));
  });

  test('expired source rules and timeouts show different actions', () {
    final expired = NetworkException(
      type: NetworkExceptionType.badResponse,
      statusCode: 404,
      message: 'redacted',
    );
    final timeout = NetworkException(
      type: NetworkExceptionType.connectionTimeout,
      message: 'redacted',
    );
    expect(sourceSearchFailureHint(expired), contains('规则'));
    expect(sourceSearchFailureHint(timeout), contains('超时'));
  });

  test('failure text never leaks site URL or user credentials', () {
    final error = SearchErrorException('demo', cause: Exception(
        'https://private.example/video?token=SECRET-DO-NOT-LOG'));
    final hint = sourceSearchFailureHint(error);
    expect(hint, isNot(contains('SECRET')));
    expect(hint, contains('失败'));
  });
}
