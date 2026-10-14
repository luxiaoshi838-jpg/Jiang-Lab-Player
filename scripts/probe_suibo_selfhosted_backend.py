"""Probe a fresh, ephemeral danmu_api checkout for real title/episode/comments.

This is NOT a substitute for a persistent backend in released Suibo builds.
Do not log comment bodies, request headers or credentials.
"""
import json
import os
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("SUIBO_LOCAL_DANMU_URL", "http://127.0.0.1:9321").rstrip("/")
WORKS = ("凡人修仙传", "亮剑")

def fetch(path, query=None):
    url = BASE + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    with urllib.request.urlopen(
        urllib.request.Request(url, headers={"Accept": "application/json"}),
        timeout=32,
    ) as response:
        raw = response.read(4_000_001)
    if len(raw) > 4_000_000:
        raise ValueError("oversized response")
    doc = json.loads(raw)
    if not isinstance(doc, dict) or doc.get("success") is False:
        raise ValueError("invalid provider response")
    return doc

def clean_title(value):
    value = re.sub(r"\((?:19|20)[0-9]{2}\)|（(?:19|20)[0-9]{2}）", "", value.split("【")[0])
    return re.sub(r"[^\w\u4e00-\u9fff]", "", value).lower()

def main():
    # Only probe the local listener. Do not launch an expensive full-source
    # title search just to test whether the Node process has started.
    for attempt in range(25):
        try:
            with socket.create_connection(("127.0.0.1", 9321), timeout=2):
                break
        except OSError:
            time.sleep(2)
    else:
        print("BACKEND_STARTUP_FAIL")
        return 2
    all_pass = True
    for title in WORKS:
        try:
            candidates = fetch("/api/v2/search/anime", {"keyword": title}).get("animes", [])
            exact = [x for x in candidates if isinstance(x, dict) and
                     clean_title(str(x.get("animeTitle", ""))) == clean_title(title)]
            print(f"SEARCH {title}: total={len(candidates)}, exact={len(exact)}", flush=True)
            ok = False
            for work in exact[:5]:
                anime_id = work.get("animeId")
                if not anime_id:
                    continue
                detail = fetch("/api/v2/bangumi/" + urllib.parse.quote(str(anime_id), safe=""))
                episodes = detail.get("bangumi", {}).get("episodes", [])
                eps = [x for x in episodes if isinstance(x, dict) and
                       re.search(r"^(?:第\s*0*1\s*[集话期]|0*1$|(?:ep|e)0*1$)",
                                 str(x.get("episodeTitle", "")).strip(), re.I)]
                if not eps and len(episodes) == 1:
                    eps = episodes
                for ep in eps[:2]:
                    episode_id = ep.get("episodeId")
                    if not episode_id:
                        continue
                    comments = fetch("/api/v2/comment/" + urllib.parse.quote(str(episode_id), safe=""),
                                     {"format": "json"}).get("comments", [])
                    count = len(comments) if isinstance(comments, list) else 0
                    print(f"EPISODE {title}: comments={count}", flush=True)
                    if count > 0:
                        ok = True
                        break
                if ok:
                    break
            all_pass = all_pass and ok
            print(f"REAL_BACKEND {title}: {'PASS' if ok else 'FAIL'}", flush=True)
        except Exception as exc:
            all_pass = False
            print(f"REAL_BACKEND {title}: {type(exc).__name__}", flush=True)
    return 0 if all_pass else 1

if __name__ == "__main__":
    sys.exit(main())
