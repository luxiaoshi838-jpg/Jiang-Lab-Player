"""Live network probe for the actual third-party CMS home catalogues.

No test fixtures, generated titles or placeholder covers are counted.
Results are diagnostic; geographical API blocks are reported explicitly.
"""
import json
import sys
import urllib.parse
import urllib.request

FEED = "https://raw.githubusercontent.com/25175/tvyuan/master/tvbox.json"
KEYWORDS = ("电影", "电视剧", "连续剧", "国产剧", "短剧", "微短剧")


def read(url):
    req = urllib.request.Request(
        url, headers={"User-Agent": "Suibo-Real-Catalog-Probe/2.3.13",
                      "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=8) as response:
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}")
        data = response.read(512 * 1024 + 1)
        if len(data) > 512 * 1024:
            raise RuntimeError("catalog exceeds response limit")
        return json.loads(data.decode("utf-8-sig"))


def endpoint(base, **params):
    return base.rstrip("?") + "?" + urllib.parse.urlencode(params)


def probe():
    feed = read(FEED)
    candidates = []
    hosts = set()
    for site in feed.get("sites", []):
        if site.get("type") != 1:
            continue
        api = site.get("api", "").rstrip("?")
        parsed = urllib.parse.urlsplit(api)
        if parsed.scheme != "https" or "/api.php/provide/vod" not in parsed.path:
            continue
        if parsed.hostname in hosts:
            continue
        hosts.add(parsed.hostname)
        candidates.append((site.get("name", parsed.hostname), api))
    categories = {}
    any_listing = False
    for name, url in candidates[:4]:
        try:
            response = read(endpoint(url, ac="list"))
            kinds = response.get("class", [])
            if not isinstance(kinds, list):
                print(name, "class list missing", flush=True)
                continue
            matches = [(item.get("type_name", ""), str(item.get("type_id", "")))
                       for item in kinds if isinstance(item, dict)
                       and any(k in item.get("type_name", "") for k in KEYWORDS)]
            print(name, "categories:", matches[:14], flush=True)
            for category, id_value in matches[:5]:
                if not id_value:
                    continue
                try:
                    listing = read(endpoint(url, ac="videolist", t=id_value, pg=1))
                    items = listing.get("list", [])
                    if not isinstance(items, list):
                        continue
                    live = [x for x in items if isinstance(x, dict)
                            and x.get("vod_id") and x.get("vod_name")]
                    covers = sum(bool(x.get("vod_pic")) for x in live)
                    print(name, category, "real_titles=", len(live),
                          "real_covers=", covers, flush=True)
                    if live:
                        any_listing = True
                        key = next((k for k in KEYWORDS if k in category), category)
                        categories[key] = categories.get(key, 0) + len(live)
                except Exception as e:
                    print(name, category, "listing_error=", type(e).__name__, flush=True)
        except Exception as e:
            print(name, "taxonomy_error=", type(e).__name__, str(e)[:140],
                  flush=True)
    print("LIVE_CMS_CATEGORY_COUNTS", categories, flush=True)
    return any_listing


if __name__ == "__main__":
    ok = probe()
    if not ok:
        print("FAILED: no real CMS category list produced a work with vod_id + vod_name", flush=True)
        sys.exit(1)
