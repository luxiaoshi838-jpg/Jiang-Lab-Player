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
COMPAT = (os.getenv("SUIBO_DANMU_API_URL", "").strip() or "https://suibo-danmaku.onrender.com").rstrip("/")
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
        raw = r.read(8_000_001)
    if len(raw) > 8_000_000:
        raise ValueError("Oversized API response")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("Invalid API response object")
    if payload.get("success") is False:
        raise ValueError("Provider returned success=false")
    return payload


def normalize(value):
    name = str(value).split("【", 1)[0]
    name = re.sub(r"[(（](?:19|20)\d{2}[)）]", "", name)
    return "".join(re.findall(r"[\w\u4e00-\u9fff]+", name)).lower()


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
            matches = []
            for row in rows:
                if not isinstance(row, dict):
                    continue
                if normalize(row.get("animeTitle", "")) != normalize(name):
                    continue
                anime_id = row.get("animeId")
                if anime_id and anime_id not in matches:
                    matches.append(anime_id)
            if matches:
                return matches[:8]
        except Exception as exc:
            print(f"SEARCH_CHECK {name}: {type(exc).__name__}", flush=True)
    return []


def first_episodes(base, anime_id, official):
    data = get_json(base, f"/api/v2/bangumi/{anime_id}", {}, official)
    show = data.get("bangumi") or {}
    rows = show.get("episodes") if isinstance(show, dict) else None
    if not isinstance(rows, list):
        return []
    first = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        label = str(row.get("episodeTitle", "")).strip()
        ordinal = str(row.get("episodeNumber", "")).strip()
        matched = (
            re.search(r"第\\s*0*1\\s*[集话期]", label)
            or re.search(r"(?:^|[_ .-])0*1$", label)
            or re.search(r"(?:^|[_ .-])(?:ep|e)0*1(?:$|[_ .-])", label, re.I)
            or (ordinal.lstrip("0") == "1")
        )
        if matched and row.get("episodeId"):
            first.append(row["episodeId"])
    if not first and len(rows) == 1 and isinstance(rows[0], dict):
        if rows[0].get("episodeId"):
            first.append(rows[0]["episodeId"])
    return list(dict.fromkeys(first))[:3]


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
                candidates = search(base, name, official)
                print(f"CANDIDATES {name}: {len(candidates)}", flush=True)
                for show_id in candidates:
                    episode_ids = first_episodes(base, show_id, official)
                    for episode_id in episode_ids:
                        if nonempty_comments(base, episode_id, official):
                            passed = True
                            break
                    if passed:
                        break
            except Exception as exc:
                print(f"PROVIDER_CHECK {name}: {type(exc).__name__}", flush=True)
            if passed:
                break
        print(f"RESULT {name}: {'PASS' if passed else 'FAIL'}", flush=True)
        ok &= passed
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
