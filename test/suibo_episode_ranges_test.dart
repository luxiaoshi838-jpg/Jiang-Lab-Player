import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/video/episode_selection_panel.dart';

void main() {
  testWidgets('large episode lists expose sequential 50-episode ranges',
      (tester) async {
    final road = Road(
      name: '正片',
      data: List.generate(121, (i) => 'https://example.test/${i + 1}'),
      identifier: List.generate(121, (i) => '第${i + 1}集'),
    );
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 780,
            child: EpisodeSelectionPanel(
              title: '长篇测试节目',
              roads: [road],
              selectedRoad: 0,
              selectedEpisode: 1,
              downloads: const {},
              onEpisodeSelected: (episode, road) => selected.add(episode),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1-50'), findsOneWidget);
    expect(find.text('51-100'), findsOneWidget);
    expect(find.text('101-121'), findsOneWidget);
    await tester.tap(find.text('51-100'));
    await tester.pumpAndSettle();
    expect(find.text('第51集'), findsWidgets);
    await tester.tap(find.text('第51集').first);
    expect(selected, [51]);
  });

  testWidgets('less than 51 episodes do not show unnecessary page labels',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 700,
            child: EpisodeSelectionPanel(
              title: '短剧',
              roads: [
                Road(
                  name: '正片',
                  data: List.generate(50, (i) => 'episode-$i'),
                  identifier: const [],
                ),
              ],
              selectedRoad: 0,
              selectedEpisode: 1,
              downloads: const {},
              onEpisodeSelected: (_, __) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('suibo-player-range-tabs')), findsNothing);
  });
}
