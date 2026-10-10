import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/media_source_candidate.dart';

/// Ephemeral search aggregation. Never merge unrelated seasonal editions
/// or overwrite the persisted identity of a real Bangumi subject.
class MediaWorkIndex {
  static String normalized(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s·•:：.。!！?？《》〈〉【】\[\]（）(),，、]'), '');

  /// Ignore only final parenthesized production year, preserving seasons.
  static String normalizedWorkTitle(String title) {
    final text = title.trim();
    final ending = RegExp(r'[（(](?:19|20)[0-9]{2}[）)]$').firstMatch(text);
    return normalized(ending == null ? text : text.substring(0, ending.start));
  }

  static String? yearOf(BangumiItem item) {
    if (item.airDate.length >= 4 &&
        RegExp(r'^(19|20)\d{2}$').hasMatch(item.airDate.substring(0, 4))) {
      return item.airDate.substring(0, 4);
    }
    return explicitYear(item.nameCn) ?? explicitYear(item.name);
  }

  static String? explicitYear(String name) {
    final found = RegExp(r'(?:^|[（(\s])((?:19|20)\d{2})(?:[）)\s]|$)')
        .firstMatch(name);
    return found?.group(1);
  }

  static bool sameWork(BangumiItem item, String title, {String? year}) {
    final normalizedTitle = normalizedWorkTitle(title);
    if (normalizedTitle.isEmpty) return false;
    final names = [item.nameCn, item.name, ...item.alias];
    if (!names.any((name) => normalizedWorkTitle(name) == normalizedTitle)) {
      return false;
    }
    final knownYear = yearOf(item);
    return year == null || knownYear == null || knownYear == year;
  }

  static BangumiItem? uniqueMatch(List<BangumiItem> works, String title,
      {String? year}) {
    final matches =
        works.where((work) => sameWork(work, title, year: year)).toList();
    return matches.length == 1 ? matches.single : null;
  }

  static void addMetadata(List<BangumiItem> works, BangumiItem incoming) {
    if (works.any((existing) => existing.id == incoming.id)) return;
    final title = incoming.nameCn.isNotEmpty ? incoming.nameCn : incoming.name;
    final match = uniqueMatch(works, title, year: yearOf(incoming));
    if (match == null) {
      works.add(incoming);
      return;
    }
    // A genuine Bangumi item always wins. External metadata replaces a
    // rule-only shell, but another catalog cannot replace existing metadata.
    if (!match.isExternal) return;
    final existingIsCatalog = match.sourcePlugin == '百科影视目录' ||
        match.sourcePlugin == 'TVmaze节目目录';
    final incomingIsCatalog = incoming.sourcePlugin == '百科影视目录' ||
        incoming.sourcePlugin == 'TVmaze节目目录';
    if (incoming.isExternal && (existingIsCatalog || !incomingIsCatalog)) {
      return;
    }
    incoming.discoveredSources.addAll(match.discoveredSources);
    if (!existingIsCatalog) {
      addCandidate(incoming, MediaSourceCandidate(
        pluginName: match.sourcePlugin,
        title: match.nameCn,
        url: match.sourceUrl,
      ));
    }
    works[works.indexOf(match)] = incoming;
  }

  static void addCandidate(BangumiItem item, MediaSourceCandidate candidate) {
    if (!item.discoveredSources.any((source) =>
        source.identity == candidate.identity)) {
      item.discoveredSources.add(candidate);
    }
  }

  static void addRuleHit(List<BangumiItem> works,
      MediaSourceCandidate candidate) {
    final title = candidate.title.trim();
    if (title.isEmpty || candidate.url.trim().isEmpty) return;
    final year = explicitYear(title);
    final match = uniqueMatch(works, title, year: year);
    if (match != null) {
      addCandidate(match, candidate);
      return;
    }
    final shell = BangumiItem.fromRule(
      pluginName: candidate.pluginName, source: candidate.url, title: title,
    );
    addCandidate(shell, candidate);
    works.add(shell);
  }
}
