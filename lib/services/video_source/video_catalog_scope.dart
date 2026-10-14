/// Live broadcasting is intentionally outside Suibo's video-catalog scope.
/// Only recognize *unambiguous* live-only providers or live rule types; do not
/// use title keywords, which would hide recorded concerts or live replays.
bool isLiveOnlyRule(String ruleType) {
  const types = {'live', 'live_stream', 'livestream'};
  return types.contains(ruleType.trim().toLowerCase());
}

bool isKnownLivePage(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return false;
  }
  const hosts = {
    'live.bilibili.com',
    'live.douyin.com',
    'live.kuaishou.com',
    'live.huya.com',
    'live.douyu.com',
  };
  return hosts.contains(uri.host.toLowerCase());
}

/// Legacy Kazumi rules declare 'anime' as their content type. Do not search
/// anime-only sites by default for a confirmed live-action movie/TV work;
/// this previously produced 16 useless "no results" rows and slow requests.
/// Unknown or multi-category rules remain eligible, never silently deleted.
bool isRelevantRuleTypeForDrama(String ruleType) =>
    ruleType.trim().toLowerCase() != 'anime';

/// Catalogue records do not have a Bangumi type; resolve these explicitly.
bool isConfirmedDramaCatalogue(int bangumiType, String sourcePlugin) =>
    bangumiType == 6 ||
    sourcePlugin == '百科影视目录' ||
    sourcePlugin == 'TVmaze节目目录';
