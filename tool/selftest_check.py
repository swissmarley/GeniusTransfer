#!/usr/bin/env python3
"""Checks a GeniusTransfer host running a self-test build, from this Mac.

Build and start the app with --dart-define=GT_SELFTEST=true; it logs
GT_SELFTEST_URL=<url>. Then run:

    python3 -I tool/selftest_check.py <url>

It acts like a guest browser: loads the page, downloads every test file,
checks sizes and checksums against the known content (byte i is
(i * 31 + 7) & 0xff), and checks Range requests, the token gate and the
security headers. Standard library only.
"""

import hashlib
import re
import sys
import time
import urllib.error
import urllib.request

FILES = {
    "selftest-small.txt": 1000,
    "selftest-photo.heic": 3 * 1000 * 1000,
    "selftest-video.mp4": 50 * 1000 * 1000,
}
SAFARI_IPHONE = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
)


def expected_bytes(start, end):
    return bytes(((i * 31 + 7) & 0xFF) for i in range(start, end))


def expected_sha256(size):
    h = hashlib.sha256()
    chunk = 1 << 20
    for offset in range(0, size, chunk):
        h.update(expected_bytes(offset, min(size, offset + chunk)))
    return h.hexdigest()


def fetch(url, headers=None, method="GET"):
    req = urllib.request.Request(url, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(name)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    url = sys.argv[1].rstrip("/") + "/"
    base, token = url[: url.rstrip("/").rfind("/") + 1], url.rstrip("/").rsplit("/", 1)[1]

    status, headers, body = fetch(url, {"User-Agent": SAFARI_IPHONE})
    page = body.decode("utf-8", "replace")
    check("page loads", status == 200, f"HTTP {status}")
    check("page lists the files", all(n in page for n in FILES))
    check("page has the iPhone note", "Files app › Downloads" in page)
    check("page makes no outside requests", "http://" not in page and "https://" not in page)
    csp = headers.get("Content-Security-Policy", headers.get("content-security-policy", ""))
    check("CSP header", "default-src 'none'" in csp)

    links = re.findall(r'href="(f/\d+/[^"]+)"', page)
    check("one download link per file", len(links) == len(FILES), f"{len(links)} links")

    for link in links:
        name = urllib.request.unquote(link.split("/", 2)[2])
        size = FILES.get(name)
        started = time.time()
        status, headers, body = fetch(url + link)
        seconds = max(time.time() - started, 1e-6)
        check(f"{name}: HTTP 200", status == 200, f"HTTP {status}")
        check(f"{name}: size", len(body) == size, f"{len(body)} bytes")
        check(f"{name}: checksum", hashlib.sha256(body).hexdigest() == expected_sha256(size))
        disposition = headers.get("Content-Disposition", headers.get("content-disposition", ""))
        check(f"{name}: attachment", disposition.startswith("attachment;"), disposition)
        print(f"     {len(body) / seconds / 1e6:.1f} MB/s")

        start = size // 3
        end = min(size - 1, start + 999)
        status, headers, part = fetch(url + link, {"Range": f"bytes={start}-{end}"})
        check(f"{name}: Range", status == 206 and part == expected_bytes(start, end + 1),
              f"HTTP {status}, {len(part)} bytes")

    wrong = token[:-1] + ("A" if token[-1] != "A" else "B")
    status, _, body = fetch(base + wrong + "/")
    check("wrong token is refused", status == 404 and b"selftest" not in body, f"HTTP {status}")
    status, _, body = fetch(base)
    check("no token is refused", status == 404 and b"selftest" not in body, f"HTTP {status}")

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {', '.join(failures)}")
        sys.exit(1)
    print("All checks passed.")


if __name__ == "__main__":
    main()
