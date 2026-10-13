import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/smoke_real_plugin.dart' as publicVod;
import '../tool/smoke_real_cms.dart' as defaultCms;

/// Runs only in the dedicated network smoke workflow. Flutter's test binding
/// normally installs a fake HTTP client; opt in to live requests here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real published VOD through the Suibo rule engine', () async {
    HttpOverrides.global = null;
    await publicVod.main();
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('real auto-discovered CMS search, poster, episodes and HLS', () async {
    HttpOverrides.global = null;
    await defaultCms.main();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
