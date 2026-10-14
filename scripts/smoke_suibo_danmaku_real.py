"""End-to-end network diagnostics for drama episode comment availability.

Prints results for real catalogue entries; 0 is NOT treated as success.
Does not store video URL, comments, credentials or downloaded media.
"""
import json
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

CMS = [
    "https://360zy.com/api.php/provide/vod",
    "https://api.wsyzy.net/api.php/provide/vod",
]
WORKS = ["亮剑", "知否知否应是绿肥红瘦"]
DANMU = "https://api.danmu.icu/"


def request(url, limit=3_000_000):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Suibo-2.3.13-Danmaku-Verification",
        "Accept": "application/json,text/xml,*/*",
    })
    with urllib.request.urlopen(req, timeout=8) as response:
        data = response.read(limit + 1)
        if len(data) > limit:
            raise ValueError("response too large")
        return data.decode("utf-8-sig", errors="replace")


def cms(endpoint, **query):
    return json.loads(request(endpoint + "?" + urllib.parse.urlencode(query)))


def episode_url(work):
    routes = str(work.get("vod_play_url", "")).split("$$$")
    for route in routes:
        for entry in route.split("#"):
            url = entry.rsplit("$", 1)[-1].strip()
            parsed = urllib.parse.urlparse(url)
            if parsed.scheme != "https" or parsed.query or parsed.username:
                continue
            if parsed.path.lower().endswith((".m3u8", ".mp4", ".m4v")):
                return url
    return None


def parse_count(raw):
    try:
        tree = ET.fromstring(raw)
        return len(tree.findall(".//d"))
    except ET.ParseError:
        try:
            obj = json.loads(raw)
            if isinstance(obj, dict):
                rows = obj.get("danmuku") or obj.get("danmu") or obj.get("comments")
                return len(rows) if isinstance(rows, list) else 0
        except ValueError:
            pass
    return 0


def run():
    missing = []
    for title in WORKS:
        found_video = False
        found_comments = False
        for provider in CMS:
            try:
                result = cms(provider, ac="videolist", wd=title)
                works = result.get("list", [])
                work = next((entry for entry in works if isinstance(entry, dict)
                    and (title in str(entry.get("vod_name", "")) or
                         str(entry.get("vod_name", "")) in title)
                    and entry.get("vod_id")), None)
                if not work:
                    continue
                detail = cms(provider, ac="videolist", ids=work["vod_id"])
                records = detail.get("list", [])
                if not records:
                    continue
                found_video = True
                video = episode_url(records[0])
                if not video:
                    print(title, "CMS video found; no safe public first-episode URL", flush=True)
                    continue
                req_url = DANMU + "?" + urllib.parse.urlencode(
                    {"ac": "dm", "url": video})
                count = parse_count(request(req_url))
                print(title, "public danmu.icu count:", count, flush=True)
                if count:
                    found_comments = True
                    break
            except Exception as exc:
                print(title, "provider/API error:", type(exc).__name__,
                      str(exc)[:120], flush=True)
        print(title, "CMS_MATCH=", found_video,
              "ACTUAL_DANMAKU=", found_comments, flush=True)
        if not found_comments:
            missing.append(title)
    if missing:
        print("FAIL: no actual danmaku for:", ", ".join(missing), flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(run())
