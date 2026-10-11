#!/usr/bin/env python3
"""Real Bangumi TV/film API smoke: exact catalog, cover, search and no keys."""
import json
import sys
import urllib.request

HEADERS = {
  "User-Agent": "SuiboCatalogDiagnostic/1.0 (https://github.com/luxiaoshi838-jpg/Jiang-Lab-Player)",
  "Accept": "application/json",
  "Content-Type": "application/json",
}
BASE = "https://api.bgm.tv"

def request(url, data=None):
    payload = None if data is None else json.dumps(data, ensure_ascii=False).encode()
    req = urllib.request.Request(BASE+url, data=payload, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=18) as r:
        return json.load(r)

def main():
    subject=request("/v0/subjects/127063")
    assert subject["id"]==127063 and subject["type"]==6, "real subject invalid"
    print("SUBJECT",subject.get("name"),"date",subject.get("date"),
          "cover",bool((subject.get("images") or {}).get("large")),
          "rank",bool((subject.get("rating") or {}).get("rank")))
    response=request("/v0/search/subjects?limit=20&offset=0",{
      "keyword":"亮剑","sort":"match","filter":{"type":[2,6],"nsfw":False}})
    raw=response.get("data") or []
    found=[v for v in raw if v.get("id")==127063]
    print("SEARCH",len(raw),"matched",bool(found),"first",
          [(x.get("name"),x.get("type")) for x in raw[:5]])
    assert found, "Real drama was not returned by mixed search"
    cover=(subject.get("images") or {}).get("large", "")
    assert cover.startswith("https://"), "Official Bangumi poster requires HTTPS"
    image_request=urllib.request.Request(cover,headers={
      "User-Agent":"SuiboCatalogDiagnostic/1.0 (https://github.com/luxiaoshi838-jpg/Jiang-Lab-Player)",
      "Accept":"image/avif,image/webp,image/jpeg,image/png,*/*"
    })
    with urllib.request.urlopen(image_request,timeout=12) as img:
      image_bytes=img.read(64)
      content_type=img.headers.get("content-type","")
      status=img.status
    if status!=200 or len(image_bytes)<16 or not (
      image_bytes.startswith(bytes.fromhex("ffd8ff")) or
      image_bytes.startswith(bytes.fromhex("89504e47")) or
      image_bytes.startswith(b"RIFF") or
      image_bytes.startswith(bytes.fromhex("000000"))
    ):
      raise RuntimeError("Official poster URL did not return an image")
    print("POSTER HTTP",status,"content-type",content_type)
    print("PASS real Chinese drama metadata search and retrievable poster")
    return 0

if __name__=="__main__":
    try: sys.exit(main())
    except Exception as exc:
        print("FAIL",type(exc).__name__,str(exc)[:120],file=sys.stderr)
        sys.exit(1)
