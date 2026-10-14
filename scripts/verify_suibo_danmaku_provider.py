"""Release gate: real search -> episode -> nonempty comments. No credentials in logs."""
import base64
import hashlib
import json
import os
import re
import sys
import time
from urllib.parse import urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

OFFICIAL = "https://api.dandanplay.net"
APPID = os.getenv("DANDANAPI_APPID", "").strip()
KEY = os.getenv("DANDANAPI_KEY", "").strip()
COMPAT = os.getenv("SUIBO_DANMU_API_URL", "").strip().rstrip("/")
WORKS = ("凡人修仙传", "亮剑")


def safe_compat():
    if not COMPAT:
        return ""
    uri = urlsplit(COMPAT)
    if uri.scheme != "https" or not uri.hostname or uri.username or uri.query or uri.fragment:
        raise ValueError("SUIBO_DANMU_API_URL is not a valid HTTPS base URL")
    if uri.hostname in ("api.danmu.icu", "api.dandanplay.net"):
        raise ValueError("URL-only danmu API is not compatible with title search")
    return COMPAT


def get_json(base, path, query, official=False):
    qs = urlencode(query, doseq=True)
    url = f"{base}{path}?{qs}"
    headers = {"User-Agent": "Suibo-Provider-Verification/2.3.15", "Accept": "application/json"}
    if official:
        stamp = str(int(time.time()))
        digest = hashlib.sha256((APPID + stamp + path + KEY).encode()).digest()
        headers.update({
            "X-Auth": "1", "X-AppId": APPID, "X-Timestamp": stamp,
            "X-Signature": base64.b64encode(digest).decode(),
        })
    req = Request(url, headers=headers)
    with urlopen(req, timeout=12) as r:
        raw = r.read(3_000_001)
    if len(raw) > 3_000_000:
        raise ValueError("Oversized API response")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("Invalid API response object")
    if payload.get("success") is False:
        raise ValueError("Provider returned success=false")
    return payload


def normalize(value):
    name = str(value).split("【", 1)[0]
    name = re.sub(r"[(（](?:19|20)\\d{2}[)）]", "", name)
    return "".join(re.findall(r"[\\w\\u4e00-\\u9fff]+", name)).lower()


def search(base, name, official):
    variants = [
        ("/api/v2/search/episodes", {"anime": name, "v2": "true"}),
    ]
    if not official:
        variants.append(("/api/v2/search/anime", {"keyword": name}))
    for path, args in variants:
        try:
            data = get_json(base, path, args, official)
            rows = data.get("animes")
            if not isinstance(rows, list):
                continue
            matches = [r for r in rows if isinstance(r, dict) and
                       normalize(r.get("animeTitle", "")) == normalize(name)]
            if len(matches) == 1:
                return matches[0].get("animeId")
        except Exception as exc:
            print(f"SEARCH_CHECK {name}: {type(exc).__name__}", flush=True)
    return None


def first_episode(base, anime_id, official):
    data = get_json(base, f"/api/v2/bangumi/{anime_id}", {}, official)
    show = data.get("bangumi") or {}
    rows = show.get("episodes") if isinstance(show, dict) else None
    if not isinstance(rows, list):
        return None
    first = [r for r in rows if isinstance(r, dict) and
             re.search(r"^(?:第\\s*0*1\\s*[集话期]|0*1$|(?:ep|e)0*1$)",
                       str(r.get("episodeTitle", "")).strip(), re.I)]
    if len(first) == 1:
        return first[0].get("episodeId")
    if len(rows) == 1 and isinstance(rows[0], dict):
        return rows[0].get("episodeId")
    return None


def nonempty_comments(base, episode_id, official):
    data = get_json(base, f"/api/v2/comment/{episode_id}", {"format": "json"}, official)
    rows = data.get("comments")
    return isinstance(rows, list) and any(
        isinstance(row, dict) and str(row.get("m", "")).strip() and row.get("p")
        for row in rows
    )


def main():
    providers = []
    if APPID and KEY:
        providers.append((OFFICIAL, True))
    compat = safe_compat()
    if compat:
        providers.append((compat, False))
    if not providers:
        print("FAIL NO_DANMAKU_PROVIDER: no real title-search service is configured")
        return 2
    ok = True
    for name in WORKS:
        passed = False
        for base, official in providers:
            try:
                show_id = search(base, name, official)
                if not show_id:
                    continue
                episode_id = first_episode(base, show_id, official)
                if episode_id and nonempty_comments(base, episode_id, official):
                    passed = True
                    break
            except Exception as exc:
                print(f"PROVIDER_CHECK {name}: {type(exc).__name__}", flush=True)
        print(f"RESULT {name}: {'PASS' if passed else 'FAIL'}", flush=True)
        ok &= passed
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
