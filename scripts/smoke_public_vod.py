#!/usr/bin/env python3
"""Real network smoke check of the bundled public PeerTube VOD provider.

No API token, credentials, unauthorized DRM bypass, fake fixture, or website
scraping. This tests discover -> detail -> public HLS manifest metadata.
"""
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://peertube.tv"
HEADERS = {"Accept": "application/json", "User-Agent": "Suibo-VOD-Smoke/1.0"}


def fetch_json(url):
    with urllib.request.urlopen(
        urllib.request.Request(url, headers=HEADERS), timeout=15
    ) as response:
        if response.status != 200:
            raise RuntimeError("Public API returned non-200 status")
        return json.load(response)


def main():
    params = urllib.parse.urlencode({
        "search": "linux",
        "count": "15",
        "isLive": "false",
        "nsfw": "false",
    })
    search = fetch_json(BASE + "/api/v1/search/videos?" + params)
    videos = search.get("data")
    if not isinstance(videos, list) or not videos:
        raise RuntimeError("Real PeerTube search returned no videos")
    checked = 0
    for video in videos[:12]:
        uuid = video.get("uuid")
        if not isinstance(uuid, str) or not uuid:
            continue
        checked += 1
        detail = fetch_json(BASE + "/api/v1/videos/" +
                            urllib.parse.quote(uuid, safe=""))
        playlists = detail.get("streamingPlaylists")
        if not isinstance(playlists, list):
            continue
        for playlist in playlists:
            raw = playlist.get("playlistUrl")
            if not isinstance(raw, str):
                continue
            url = urllib.parse.urlparse(raw)
            if url.scheme != "https" or not url.hostname or not url.path.endswith(".m3u8"):
                continue
            # Fetch only the small manifest, never download video segments.
            # A nominal playlist URL can still be a 404, HTML or forbidden page.
            try:
                request = urllib.request.Request(raw, headers={
                    "Accept": "application/vnd.apple.mpegurl",
                    "User-Agent": "Suibo-VOD-Smoke/1.0",
                })
                with urllib.request.urlopen(request, timeout=12) as response:
                    manifest = response.read(32768)
                if not manifest.lstrip().startswith(b"#EXTM3U"):
                    continue
            except urllib.error.URLError:
                continue
            print("PASS: public search -> detail -> fetched valid HLS manifest")
            print("Public result title:", str(video.get("name", ""))[:90])
            print("Public HLS host:", url.hostname)
            return 0
    raise RuntimeError(
        "Public search succeeded but no HLS playlist found after " +
        str(checked) + " video details"
    )


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, urllib.error.URLError, ValueError, KeyError) as error:
        print("PUBLIC VOD SMOKE FAILED:", str(error).split("?")[0], file=sys.stderr)
        sys.exit(1)
