#!/usr/bin/env python3
"""End-to-end CMS playback probe: metadata -> episode -> HLS -> first media bytes.

A title, poster, HTTP 200, or HLS manifest alone is NOT playback acceptance.
Only query public endpoints; never bypass DRM, cookies, authentication or paywalls.
Never log full media URLs, tokens or personally identifying request headers.
"""
import ipaddress
import json
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass

FEED = "https://raw.githubusercontent.com/25175/tvyuan/master/tvbox.json"
UA = "Suibo-Playback-Probe/2.3"
MAX_API_BYTES = 400_000
MAX_MEDIA_BYTES = 8192


def safe(url):
    try:
        u = urllib.parse.urlsplit(url)
        if u.scheme not in ("http", "https") or not u.hostname or u.username:
            return False
        if u.hostname == "localhost" or u.hostname.endswith(".local"):
            return False
        try:
            if not ipaddress.ip_address(u.hostname).is_global:
                return False
        except ValueError:
            pass
        return True
    except ValueError:
        return False


def fetch(url, *, limit=MAX_API_BYTES, headers=None):
    if not safe(url):
        raise ValueError("non-public URL")
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "application/json,text/plain,application/vnd.apple.mpegurl,*/*",
        **(headers or {}),
    })
    with urllib.request.urlopen(req, timeout=9) as res:
        if res.status not in (200, 206):
            raise ValueError("unexpected status")
        return res.read(limit)


def api(endpoint, **params):
    url = endpoint + ("&" if "?" in endpoint else "?") + urllib.parse.urlencode(params)
    return json.loads(fetch(url).decode("utf-8-sig"))


def vod_urls(detail):
    items = detail.get("list", []) if isinstance(detail, dict) else []
    if not isinstance(items, list) or not items:
        return []
    video = items[0]
    all_urls = []
    roads = str(video.get("vod_play_url", "")).split("$$$")
    for road in roads:
        for cell in road.split("#")[:3]:
            addr = cell.rsplit("$", 1)[-1].strip()
            if not safe(addr):
                continue
            path = urllib.parse.urlsplit(addr).path.lower()
            if path.endswith((".m3u8", ".mp4", ".m4v")):
                all_urls.append(addr)
    return list(dict.fromkeys(all_urls))[:4]


def first_hls_segment(url, depth=0):
    if depth > 2:
        raise ValueError("manifest nesting limit")
    raw = fetch(url, limit=80_000).decode("utf-8-sig", errors="replace")
    if not raw.lstrip().startswith("#EXTM3U"):
        raise ValueError("not an HLS manifest")
    lines = [x.strip() for x in raw.splitlines() if x.strip()]
    if any(x.startswith("#EXT-X-KEY:") or x.startswith("#EXT-X-SESSION-KEY:") for x in lines):
        raise ValueError("encrypted or rights-controlled HLS")
    for i, line in enumerate(lines):
        if line.startswith("#EXT-X-STREAM-INF:") and i + 1 < len(lines):
            url2 = urllib.parse.urljoin(url, lines[i + 1])
            if not safe(url2):
                raise ValueError("non-public variant")
            return first_hls_segment(url2, depth + 1)
    segments = [line for line in lines if not line.startswith("#")]
    if not segments:
        raise ValueError("manifest contains no media segments")
    url2 = urllib.parse.urljoin(url, segments[0])
    if not safe(url2):
        raise ValueError("non-public segment")
    return fetch(url2, limit=MAX_MEDIA_BYTES, headers={"Range": "bytes=0-8191"})


def first_bytes(url):
    path = urllib.parse.urlsplit(url).path.lower()
    if path.endswith(".m3u8"):
        return first_hls_segment(url)
    return fetch(url, limit=MAX_MEDIA_BYTES, headers={"Range": "bytes=0-8191"})


def recognizable_media(data):
    if len(data) < 16:
        return False
    if data[0] == 0x47 or (len(data) > 188 and data[188] == 0x47):
        return True  # MPEG transport packets
    return any(x in data[:64] for x in (b"ftyp", b"styp", b"moof", b"mdat", b"ID3"))


def main():
    feed = json.loads(fetch(FEED).decode("utf-8-sig"))
    raw = feed.get("sites", []) if isinstance(feed, dict) else []
    sites, used = [], set()
    for item in raw if isinstance(raw, list) else []:
        if not isinstance(item, dict) or item.get("type") != 1:
            continue
        url = str(item.get("api", ""))
        if not safe(url) or "/api.php/provide/vod" not in urllib.parse.urlsplit(url).path:
            continue
        host = urllib.parse.urlsplit(url).hostname
        if host not in used:
            sites.append((str(item.get("name", "CMS"))[:36], url))
            used.add(host)
        if len(sites) == 4:
            break

    counters = dict(category_results=0, exact_details=0,
                    direct_media_links=0, media_bytes=0)
    for name, endpoint in sites:
        try:
            listing = api(endpoint, ac="list")
            kinds = listing.get("class") or []
            groups = [r for r in kinds if isinstance(r, dict) and
                      any(w in str(r.get("type_name", "")) for w in ("国产剧", "电视剧", "电影", "短剧"))][:3]
            for kind in groups:
                catalog = api(endpoint, ac="videolist", t=kind["type_id"], pg=1)
                titles = catalog.get("list") or []
                for title in titles[:2]:
                    if not isinstance(title, dict) or not title.get("vod_id"):
                        continue
                    counters["category_results"] += 1
                    try:
                        detail = api(endpoint, ac="detail", ids=str(title["vod_id"]))
                        if not detail.get("list"):
                            continue
                        counters["exact_details"] += 1
                        links = vod_urls(detail)
                        counters["direct_media_links"] += len(links)
                        for link in links[:2]:
                            try:
                                data = first_bytes(link)
                                if recognizable_media(data):
                                    counters["media_bytes"] += 1
                                    print("PLAYBACK_BYTES_OK source=", name,
                                          "media_host=", urllib.parse.urlsplit(link).hostname, flush=True)
                                    break
                            except Exception as exc:
                                reason = str(exc) if isinstance(exc, ValueError) else type(exc).__name__
                                if len(reason) > 80:
                                    reason = reason[:80]
                                print("MEDIA_UNAVAILABLE", reason, flush=True)
                    except Exception as exc:
                        print("DETAIL_UNAVAILABLE", type(exc).__name__, flush=True)
        except Exception as exc:
            print("SOURCE_UNAVAILABLE", name, type(exc).__name__, flush=True)
    print("PLAYBACK_CHAIN_METRICS", json.dumps(counters, sort_keys=True), flush=True)
    if counters["media_bytes"] == 0:
        print("FAIL: catalog and manifest are not proof of playable video", flush=True)
        return 1
    print("PASS: public media bytes received (not a decoder/frame-level test)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
