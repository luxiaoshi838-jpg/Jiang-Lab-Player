import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/card/bangumi_card.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/pages/popular/home_media_category.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/device.dart';

/// Four independent home sections; exactly twelve slots each.
class HomeRecommendations extends StatelessWidget {
  const HomeRecommendations({super.key, required this.controller});

  final PopularController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final category in HomeMediaCategory.values)
          _HomeSection(controller: controller, category: category),
      ],
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({required this.controller, required this.category});

  final PopularController controller;
  final HomeMediaCategory category;

  @override
  Widget build(BuildContext context) {
    final columns = isDesktop() ? 6 : 3;
    final width = MediaQuery.sizeOf(context).width;
    final gap = StyleString.cardSpace;
    final tileWidth = (width - gap * 2 - 16 - (columns - 1) * gap) / columns;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 0, 6),
            child: Row(
              children: [
                Expanded(
                  child: Observer(builder: (_) {
                    final selected =
                        controller.homeSelectedTags[category] ?? '';
                    final heading = selected.isEmpty
                        ? category.popularTitle
                        : '${category.label} · $selected';
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: KazumiMenuButton(
                        animated: true,
                        style: const MenuStyle(
                          maximumSize:
                              WidgetStatePropertyAll(Size(240, 350)),
                        ),
                        menuChildren: [
                          for (final tag in [
                            '',
                            ...category.subcategories,
                          ])
                            KazumiMenuItem(
                              label: tag.isEmpty
                                  ? category.popularTitle
                                  : tag,
                              selected: tag == selected,
                              onPressed: () =>
                                  controller.selectHomeSubcategory(
                                      category, tag),
                            ),
                        ],
                        builder: (context, toggle) => InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: toggle,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    heading,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                IconButton(
                  tooltip: '刷新${category.label}',
                  onPressed: () => controller.refreshHomeSection(category),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Observer(builder: (_) {
            final items = controller.homeItems[category]!;
            final loading = controller.homeLoading[category] ?? false;
            if (items.isEmpty) {
              return SizedBox(
                height: 72,
                child: Center(
                  child: loading
                      ? const CircularProgressIndicator()
                      : Text(controller.homeFailed[category] == true
                          ? '暂无符合此分类的作品，可换个标签或刷新'
                          : '暂无此分类作品'),
                ),
              );
            }
            final count = items.length > HomeMediaCategory.visibleCount
                ? HomeMediaCategory.visibleCount
                : items.length;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: gap - 2,
                crossAxisSpacing: gap,
                mainAxisExtent: tileWidth / 0.65 +
                    MediaQuery.textScalerOf(context).scale(32),
              ),
              itemCount: count,
              itemBuilder: (context, index) =>
                  BangumiCardV(bangumiItem: items[index]),
            );
          }),
        ],
      ),
    );
  }
}
