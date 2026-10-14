import 'package:flutter/material.dart';

typedef VideoPlayerLayout = ({bool fillsWindow, bool hasSidePanel});

/// Fullscreen fills the available window; rotation belongs to the OS.
class VideoPageLayout extends StatelessWidget {
  const VideoPageLayout({
    super.key,
    required this.fullscreen,
    required this.isPip,
    required this.playerBuilder,
    required this.tabs,
    this.sidePanel,
  });

  final bool fullscreen;
  final bool isPip;
  final Widget Function(BuildContext context, VideoPlayerLayout layout)
      playerBuilder;
  final Widget tabs;
  final Widget? sidePanel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Both Android and Windows keep video above the episode/comment tabs.
      // Only explicit fullscreen or picture-in-picture hides the lower area.
      final fillsWindow = fullscreen || isPip;
      const hasSidePanel = false;
      final normalHeight = (constraints.maxWidth * 9 / 16)
          .clamp(150.0, constraints.maxHeight * 0.56)
          .toDouble();
      return SafeArea(
        top: !fillsWindow,
        bottom: !fillsWindow,
        left: !fillsWindow,
        right: !fillsWindow,
        child: Column(
          children: [
            if (fillsWindow)
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: playerBuilder(context, (
                    fillsWindow: fillsWindow,
                    hasSidePanel: hasSidePanel,
                  )),
                ),
              )
            else
              SizedBox(
                height: normalHeight,
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: playerBuilder(context, (
                    fillsWindow: fillsWindow,
                    hasSidePanel: hasSidePanel,
                  )),
                ),
              ),
            if (!fillsWindow) Expanded(child: tabs),
          ],
        ),
      );
    });
  }
}
