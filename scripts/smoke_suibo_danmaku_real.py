"""Real non-empty drama danmaku smoke, never pass when comments are zero.

Primary search: public 360kan exact-title metadata -> verified official video
episode link -> public URL-based danmaku library. No video downloading.
CMS checks remain a fallback for direct public-slice links.
"""
import json
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

WORKS = ("亮剑", "知否知否应是绿肥红瘦")
CMS = ("https://360zy.com/api.php/provide/vod",
       "https://api.wsyzy.net/api.php/provide/vod")
PUBLIC = ("https://dmku.hls.one/", "https://api.danmu.icu/")
OFFICIAL = ("v.qq.com", "www.iqiyi.com", "v.youku.com",
            "www.mgtv.com", "www.bilibili.com", "www.miguvideo.com")


def request(url, limit=3_000_000):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126",
        "Accept": "application/json,text/xml,*/*",
    })
    with urllib.request.urlopen(req, timeout=9) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("response too large")
    return data.decode("utf-8-sig", errors="replace")


def decode(url, **query):
    sep = "&" if "?" in url else "?"
    return json.loads(request(url + sep + urllib.parse.urlencode(query)))


def count(raw):
    try:
        root = ET.fromstring(raw)
        return len(root.findall(".//d"))
    except ET.ParseError:
        try:
            obj = json.loads(raw)
            if isinstance(obj, dict):
                rows = obj.get("danmuku") or obj.get("danmu") or obj.get("comments")
                return len(rows) if isinstance(rows, list) else 0
        except (ValueError, TypeError):
            pass
    return 0


def clean_title(s):
    return re.sub(r"[\\W_]+", "", s).lower()


def safe_url(s, require_official=False):
    p = urllib.parse.urlparse(str(s))
    if p.scheme not in ("http", "https") or not p.hostname or p.username:
        return None
    query = urllib.parse.parse_qs(p.query)
    if any(k.lower() in {"token", "auth", "key", "signature", "sign",
                         "password", "access_token", "secret"} for k in query):
        return None
    if require_official:
        if p.hostname not in OFFICIAL:
            return None
        if p.hostname == "v.youku.com" and p.path == "/video":
            vid = query.get("vid", [""])[0]
            if not re.fullmatch(r"[A-Za-z0-9_=-]{1,100}", vid):
                return None
            return f"https://v.youku.com/v_show/id_{vid}.html"
        return p._replace(scheme="https").geturl()
    if p.scheme != "https" or p.query or not p.path.lower().endswith((".m3u8", ".mp4", ".m4v")):
        return None
    return s


def search_official(title):
    data = decode("https://api.so.360kan.com/index",
                  force_v=1, kw=title, pageno=1, v_ap=1, tab="all")
    rows = data.get("data", {}).get("longData", {}).get("rows", [])
    found = []
    print(title, "360_RESULTS=", len(rows) if isinstance(rows,list) else "wrong-shape",
          "MATCH_TITLES=", [str(r.get("titleTxt", ""))[:36] for r in rows[:8]]
          if isinstance(rows,list) else [], flush=True)
    for row in rows if isinstance(rows, list) else []:
        if clean_title(row.get("titleTxt", "")) != clean_title(title):
            continue
        print(title, "EXACT_KEYS=", sorted(row)[:22],
              "SERIES_COUNT=", len(row.get("seriesPlaylinks") or []),
              "SITES=", list((row.get("playlinks") or {}).keys())[:5],
              flush=True)
        samples = row.get("seriesPlaylinks") or []
        if samples:
            example = samples[0]
            ep = example.get("url", "") if isinstance(example, dict) else example
            parsed = urllib.parse.urlparse(str(ep))
            print(title, "FIRST_EPISODE_URL_TYPE=", type(example).__name__,
                  "FIELDS=", list(example)[:8] if isinstance(example, dict) else [],
                  "SCHEME=", parsed.scheme, "HOST=", parsed.hostname,
                  "PATH_SUFFIX=", parsed.path[-20:], flush=True)
        sites = row.get("playlinks") or {}
        print(title, "PLAYLINK_HOSTS=",
              {key: urllib.parse.urlparse(str(value)).hostname
               for key, value in list(sites.items())[:5]}, flush=True)
        if row.get("cat_name") == "电影":
            for url in sites.values():
                if safe_url(url, require_official=True):
                    found.append(safe_url(url, require_official=True))
            continue
        ep_list = row.get("seriesPlaylinks") or []
        if isinstance(ep_list, list) and ep_list:
            for entry in ep_list[:1]:
                url = entry.get("url") if isinstance(entry, dict) else ""
                if safe_url(url, require_official=True):
                    found.append(safe_url(url, require_official=True))
        if found:
            continue
        cat = 2 if row.get("cat_name") == "电视剧" else 4
        ent_id = row.get("en_id")
        if not ent_id or not isinstance(sites, dict):
            continue
        for site in tuple(sites)[:3]:
            payload = json.dumps([{"cat_id": str(cat), "ent_id": str(ent_id), "site": site}],
                                 ensure_ascii=False, separators=(",", ":"))
            try:
                result = decode("https://api.so.360kan.com/episodesv2",
                                v_ap=1, s=payload)
                blocks = result.get("data") or []
                html = blocks[0].get("seriesHTML", {}) if blocks else {}
                episodes = html.get("seriesPlaylinks") or html.get("series_playlinks") or []
                if episodes:
                    first = episodes[0]
                    url = first.get("url") if isinstance(first, dict) else first
                    if safe_url(url, require_official=True):
                        found.append(safe_url(url, require_official=True))
            except Exception as exc:
                print(title, site, "detail error:", type(exc).__name__, flush=True)
    print(title, "OFFICIAL_URLS=", len(found), flush=True)
    return list(dict.fromkeys(found))[:3]


def search_cms(title):
    found = []
    for provider in CMS:
        try:
            rows = decode(provider, ac="videolist", wd=title).get("list", [])
            item = next((x for x in rows if isinstance(x, dict) and
                         clean_title(x.get("vod_name", "")) == clean_title(title) and
                         x.get("vod_id")), None)
            if not item:
                continue
            details = decode(provider, ac="videolist", ids=item["vod_id"]).get("list") or []
            for road in str(details[0].get("vod_play_url", "")).split("$$$") if details else []:
                for episode in road.split("#")[:1]:
                    url = episode.rsplit("$", 1)[-1].strip()
                    if safe_url(url):
                        found.append(url)
        except Exception as exc:
            print(title, "CMS error:", type(exc).__name__, flush=True)
    return list(dict.fromkeys(found))[:2]


def check_public_compat(title):
    """Probe the Dandan-compatible public endpoint used by iPlay on GitHub."""
    base = "https://api.ourfor.top"
    try:
        data = decode(base + "/api/v2/search/episodes", anime=title)
        animes = data.get("animes") or []
        exact = [a for a in animes if clean_title(a.get("animeTitle", "")) == clean_title(title)]
        print(title, "OURFOR_TITLES=", len(animes), "EXACT=", len(exact), flush=True)
        if len(exact) != 1:
            return False
        first = [e for e in exact[0].get("episodes", [])
                 if re.search(r"^(?:第\\s*0*1\\s*[集话期]|0*1$)", str(e.get("episodeTitle", "")))]
        if len(first) != 1 or not first[0].get("episodeId"):
            return False
        data = decode(base + "/api/v2/comment/" + str(first[0]["episodeId"]))
        comments = data.get("comments")
        n = len(comments) if isinstance(comments, list) else 0
        print(title, "OURFOR_REAL_COMMENT_ROWS=", n, flush=True)
        return n > 0
    except Exception as exc:
        print(title, "OURFOR_ERROR=", type(exc).__name__, flush=True)
        return False


def check(title):
    if check_public_compat(title):
        return True
    urls = []
    try:
        urls.extend(search_official(title))
    except Exception as exc:
        print(title, "360 lookup:", type(exc).__name__, flush=True)
    urls.extend(search_cms(title))
    for page in urls[:5]:
        for server in PUBLIC:
            try:
                comments = count(request(server + "?" + urllib.parse.urlencode({
                    "ac": "dm", "url": page})))
                print(title, "source:", urllib.parse.urlparse(server).hostname,
                      "count:", comments, flush=True)
                if comments > 0:
                    return True
            except Exception as exc:
                print(title, "public source unavailable:",
                      type(exc).__name__, flush=True)
    return False


def main():
    failed = []
    for title in WORKS:
        has_comments = check(title)
        print(title, "ACTUAL_DANMAKU=", has_comments, flush=True)
        if not has_comments:
            failed.append(title)
    if failed:
        print("FAIL: zero real danmaku:", ", ".join(failed), flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
