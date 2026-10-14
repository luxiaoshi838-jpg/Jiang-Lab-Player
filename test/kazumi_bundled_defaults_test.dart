import 'dart:convert';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all 16 current Kazumi anime sources ship as offline defaults', () async {
    const names = <String>{
      '7sefun', 'aafun', 'AGE', 'akianime', 'baimao', 'dalvdm',
      'DM84', 'ezdmw', 'giriGiriLove', 'mgnacg', 'moonci', 'mutefun',
      'MXdm', 'sorani', 'xfdmneo', 'xfdmnext',
    };
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().where((path) =>
        path.startsWith('assets/plugins/') && path.endsWith('.json'));
    final rules = <Plugin>[];
    for (final path in assets) {
      final data = jsonDecode(await rootBundle.loadString(path));
      rules.add(Plugin.fromJson(Map<String, dynamic>.from(data as Map)));
    }
    final anime = rules.where((p) => p.type == 'anime').toList();
    expect(anime.length, names.length);
    expect(anime.map((p) => p.name).toSet(), names);
    for (final rule in anime) {
      expect(
        rule.usesApiSearch || rule.searchURL.contains('@keyword'),
        isTrue,
        reason: 'Each bundled rule must have a search strategy: ${rule.name}',
      );
      expect(rule.baseUrl, startsWith('https://'));
      expect(rule.chapterRoads.isNotEmpty ||
          rule.chapterApiConfig.request.url.isNotEmpty, isTrue,
          reason: 'Every bundled rule needs a chapter strategy: ${rule.name}');
    }
    expect(rules.any((p) => p.name == 'PeerTube公开点播'), isTrue);
  });
}
