"""Read-only probe of publicly documented danmaku endpoints.
No developer API keys, user data or secrets. Do not treat HTTP 200 as comments.
"""
import json
import urllib.parse
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET

TARGETS = [
    ("dandan-public-title-search",
     "https://api.dandanplay.net/api/v2/search/anime",
     {"keyword": "凡人修仙传", "v2": "true"}),
    ("dandan-public-episode-search",
     "https://api.dandanplay.net/api/v2/search/episodes",
     {"anime": "凡人修仙传", "v2": "true"}),
    ("danmu-icu-documented-official-video",
     "https://api.danmu.icu/",
     {"ac": "dm", "url": "https://v.qq.com/x/cover/mzc00200vkqr54u/u4100l66fas.html"}),
]


def main():
    for label, base, params in TARGETS:
        url = base + "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json,application/xml,text/xml",
        })
        try:
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = resp.read(2_000_000)
                status = resp.status
                content_type = resp.headers.get("Content-Type", "").split(";")[0]
            nonempty = False
            protocol = "unknown"
            try:
                doc = json.loads(data)
                protocol = "json"
                if isinstance(doc, dict):
                    matches = doc.get("animes") or doc.get("comments") or []
                    nonempty = isinstance(matches, list) and bool(matches)
            except (ValueError, UnicodeDecodeError):
                try:
                    xml = ET.fromstring(data)
                    protocol = "xml"
                    nonempty = len(xml.findall(".//d")) > 0
                except ET.ParseError:
                    protocol = "other"
            print(f"{label}: status={status}, type={content_type}, protocol={protocol}, nonempty={nonempty}")
        except urllib.error.HTTPError as exc:
            print(f"{label}: status={exc.code}, error=HTTPError")
        except Exception as exc:
            print(f"{label}: request_error={type(exc).__name__}")


if __name__ == "__main__":
    main()
