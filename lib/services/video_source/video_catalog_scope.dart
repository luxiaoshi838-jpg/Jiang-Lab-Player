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
