#!/usr/bin/env python3
"""Checks a GeniusTransfer host receiving files, from this Mac.

Build and start the app with
--dart-define=GT_SELFTEST=true --dart-define=GT_SELFTEST_MODE=receive;
it opens a receiving session that accepts every offer, and logs
GT_SELFTEST_URL=<url>. Then run:

    python3 -I tool/selftest_upload.py <url>

It acts like a guest browser: loads the upload page, sends three files the
way the page's script does (offer, wait for approval, one request per
file), then two more through the plain form a browser without JavaScript
uses. Byte i of every file is (i * 31 + 7) & 0xff. The app checks the
content and logs, per file:

    GT_SELFTEST_RECEIVED=<name>|<size>|ok
    GT_SELFTEST_SAVED=<final name>|<size>|<folder>|<path or URI>

Standard library only.
"""

import http.client
import json
import sys
import time
import urllib.parse

FILES = [
    ("selftest-small.txt", 1000, "text/plain"),
    ("selftest-photo.heic", 3 * 1000 * 1000, "image/heic"),
    ("selftest-video.mp4", 50 * 1000 * 1000, "video/mp4"),
]
FORM_FILES = [("selftest-small.txt", 1234), ("selftest-form é.bin", 5000)]
SAFARI_IPHONE = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
)

# The pattern repeats every 256 bytes (31 is odd), so build it once.
_BLOCK = bytes(((i * 31 + 7) & 0xFF) for i in range(256))


def content(size):
    return (_BLOCK * (size // 256 + 1))[:size]


failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(name)


class Guest:
    def __init__(self, url):
        u = urllib.parse.urlsplit(url)
        self.host, self.port = u.hostname, u.port or 80
        self.base = u.path if u.path.endswith("/") else u.path + "/"

    def request(self, method, path, body=None, headers=None, timeout=60):
        conn = http.client.HTTPConnection(self.host, self.port, timeout=timeout)
        try:
            h = {"User-Agent": SAFARI_IPHONE}
            h.update(headers or {})
            conn.request(method, self.base + path, body=body, headers=h)
            r = conn.getresponse()
            return r.status, dict(r.getheaders()), r.read()
        finally:
            conn.close()

    def json(self, method, path, payload=None, timeout=60):
        body = None if payload is None else json.dumps(payload).encode()
        headers = {"Content-Type": "application/json"} if body else {}
        status, _, data = self.request(method, path, body, headers, timeout)
        try:
            return status, json.loads(data)
        except ValueError:
            return status, None


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    g = Guest(sys.argv[1])

    status, headers, body = g.request("GET", "")
    check("upload page loads", status == 200, f"HTTP {status}")
    check("it is the upload page", b"Send files to the other device" in body)
    check("the plain form is there",
          b'enctype="multipart/form-data"' in body and b'name="f" multiple' in body)

    # The script's way: offer, wait for approval, then one request per file.
    offer = {"files": [{"name": n, "size": s, "type": t} for n, s, t in FILES]}
    status, answer = g.json("POST", "offer", offer)
    check("offer accepted for review", status == 200 and answer and "id" in answer,
          f"HTTP {status} {answer}")
    if status != 200:
        return
    batch = answer["id"]
    state = answer.get("state")
    deadline = time.time() + 90
    while state == "pending" and time.time() < deadline:
        status, answer = g.json("GET", f"offer/{batch}", timeout=40)
        state = answer.get("state") if answer else None
    check("host accepted the offer", state == "accepted", f"state {state}")
    if state != "accepted":
        return

    total = 0
    started = time.time()
    for i, (name, size, _) in enumerate(FILES):
        status, _, data = g.request(
            "POST", f"u/{batch}/{i}", content(size),
            {"Content-Type": "application/octet-stream"}, timeout=300)
        check(f"upload {name}", status == 200, f"HTTP {status} {data[:80]!r}")
        total += size
    seconds = max(time.time() - started, 0.001)
    print(f"     {total / 1e6:.1f} MB in {seconds:.1f} s "
          f"({total / 1e6 / seconds:.1f} MB/s)")

    status, answer = g.json("GET", f"offer/{batch}")
    check("batch is done", answer and answer.get("state") == "done", f"{answer}")
    status, _, _ = g.request("POST", f"u/{batch}/0", content(FILES[0][1]))
    check("a second upload of the same file is refused", status == 409,
          f"HTTP {status}")

    # The plain form, as a browser without JavaScript sends it.
    boundary = "----GeniusTransferSelfTest"
    parts = []
    for name, size in FORM_FILES:
        parts.append(
            (f"--{boundary}\r\n"
             f'Content-Disposition: form-data; name="f"; filename="{name}"\r\n'
             "Content-Type: application/octet-stream\r\n\r\n").encode("utf-8")
            + content(size) + b"\r\n")
    form = b"".join(parts) + f"--{boundary}--\r\n".encode()
    status, headers, _ = g.request(
        "POST", "u", form,
        {"Content-Type": f"multipart/form-data; boundary={boundary}"})
    location = {k.lower(): v for k, v in headers.items()}.get("location", "")
    check("plain form upload", status == 303 and location.startswith("wait/"),
          f"HTTP {status} location={location!r}")
    if status == 303:
        page = b""
        deadline = time.time() + 60
        while time.time() < deadline:
            _, _, page = g.request("GET", location)
            if b"http-equiv" not in page:
                break
            time.sleep(1)
        check("plain form: host accepted", b"2 files sent." in page,
              page[:200].decode("utf-8", "replace"))

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {', '.join(failures)}")
        sys.exit(1)
    print("All checks passed. Now check the app log for GT_SELFTEST_RECEIVED=…|ok "
          f"({len(FILES) + len(FORM_FILES)} lines) and GT_SELFTEST_SAVED=….")


if __name__ == "__main__":
    main()
