#!/usr/bin/env python3
"""VK relay for the Roku VK app (Roku OS has no VPN). The TV requests
  GET /<KEY>/https://<vk host>/<path>?<query>
and this server fetches it from VK (a server with a good route to VK) and streams it back with Range support.
Only VK hosts are allowed and a secret KEY is required, so this is not an open proxy.
Env: RELAY_KEY (required), PORT (default 8787)."""
import http.client, http.server, os, re, time, shutil, urllib.error, urllib.parse, urllib.request

KEY = os.environ["RELAY_KEY"]
ALLOWED = ("vk.com", "vk.ru", "okcdn.ru", "mycdn.me", "userapi.com", "vkuser.net", "vkuservideo.net", "vkvideo.ru")
PASS = ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Last-Modified", "ETag")
UA = "VKAndroidApp/8.120-21460 (Android 13; SDK 33; arm64-v8a; Google Pixel; ru; 2400x1080)"
PREFIX = "/" + KEY + "/"


def target(path):
    """'/KEY/https://host/x' -> 'https://host/x'. Proxies may squash '//' into '/', so accept both."""
    rest = path[len(PREFIX):]
    if rest.startswith("h/"):   # playlist form /KEY/h/host/path: Roku's HLS parser rejects a second "://"
        return "https://" + rest[2:]
    for scheme in ("https://", "https:/"):
        if rest.startswith(scheme):
            return "https://" + rest[len(scheme):]
    return ""


def allowed(url):
    p = urllib.parse.urlsplit(url)
    host = (p.hostname or "").lower()
    return p.scheme == "https" and any(host == d or host.endswith("." + d) for d in ALLOWED)


class VKOnlyRedirects(urllib.request.HTTPRedirectHandler):
    """Follow redirects only to allowed VK hosts (no SSRF via a VK open redirect)."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return super().redirect_request(req, fp, code, msg, headers, newurl) if allowed(newurl) else None


class FastConnect(http.client.HTTPSConnection):
    """~1 in 9 new server->VK connections hang in the TCP/TLS handshake (any VK IP; normal RTT 60 ms):
    give the handshake 1.5 s so fetch() can retry, then allow 30 s for VK to answer and stream."""
    def connect(self):
        self.timeout = 1.5
        super().connect()
        self.sock.settimeout(30)


class FastHTTPS(urllib.request.HTTPSHandler):
    def https_open(self, req):
        return self.do_open(FastConnect, req, context=self._context)


OPENER = urllib.request.build_opener(VKOnlyRedirects, FastHTTPS)


def fetch(url, hdr):
    for _ in range(5):
        try:
            return OPENER.open(urllib.request.Request(url, headers=hdr), timeout=30)
        except urllib.error.HTTPError as e:
            return e
        except Exception:
            continue
    return None


def playlist(body, url):
    """Rewrite a VK HLS playlist so every URI is an absolute URL back through this relay (Roku can't
    resolve relative URIs under our /KEY/https://host/ paths), and keep only 720p..1080p variants:
    the TV is FHD and the user never wants less than 720p."""
    def via(u):
        if "://" not in u and not u.startswith("/"):
            return u   # plain relative (segment names): Roku resolves it under our /KEY/h/host/ path; keeps the playlist small
        return PREFIX + "h/" + urllib.parse.urljoin(url, u).split("://", 1)[1]

    out, keep, kept = [], True, 0
    for line in body.splitlines():
        if line.startswith("#EXT-X-STREAM-INF"):
            m = re.search(r"RESOLUTION=\d+x(\d+)", line)
            keep = m is None or 720 <= int(m.group(1)) <= 1080
            kept += keep
        elif line and not line.startswith("#"):
            if keep:
                out.append(via(line))
            keep = True
            continue
        line = re.sub(r'URI="([^"]+)"', lambda m: 'URI="%s"' % via(m.group(1)), line)
        if keep:
            out.append(line)
    if "#EXT-X-STREAM-INF" in body and not kept:
        return playlist(body.replace("RESOLUTION=", "X-RES="), url)   # no HD variant: keep all rather than nothing
    return "\n".join(out) + "\n"


def best_variant(master, url):
    """URL of the 1080p variant (else the tallest one <= 1080p) of a master playlist, or None for a media playlist."""
    best, h, lines = None, -1, master.splitlines()
    for i, line in enumerate(lines[:-1]):
        m = re.search(r"RESOLUTION=\d+x(\d+)", line) if line.startswith("#EXT-X-STREAM-INF") else None
        if m and h < int(m.group(1)) <= 1080:
            best, h = urllib.parse.urljoin(url, lines[i + 1].strip()), int(m.group(1))
    return best


def note(h, status, size, t0):
    """One line per request without the URL (it carries tokens): method, file kind, status, size, seconds."""
    path = urllib.parse.urlsplit(h.path).path
    kind = "api" if "/method/" in path else path.rsplit(".", 1)[-1][:6] if "." in path[-12:] else "file"
    print(h.command, kind, status, size, "%.2fs" % (time.time() - t0), h.headers.get("Range", ""), flush=True)


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 60  # idle keep-alive connections die instead of pinning threads

    def do_HEAD(self):
        self.do_GET(head=True)

    def do_GET(self, head=False):
        t0 = time.time()
        if self.path == "/health":
            return self._plain(200, b"ok")
        url = target(self.path) if self.path.startswith(PREFIX) else ""
        if not allowed(url):
            return self._plain(404, b"not found")
        hdr = {"User-Agent": UA}
        if self.headers.get("Range"):
            hdr["Range"] = self.headers["Range"]
        up = fetch(url, hdr)
        if up is None:
            return self._plain(502, b"upstream error")
        if "mpegurl" in (up.headers.get("Content-Type") or "").lower():
            text, src = up.read().decode("utf-8", "replace"), up.geturl()
            up.close()
            pick = best_variant(text, src)
            if pick:   # Roku stalls on VK's master playlist: redirect straight to the 1080p (else best <=1080p) variant
                self.send_response(302)
                self.send_header("Location", PREFIX + "h/" + pick.split("://", 1)[1])
                self.send_header("Content-Length", "0")
                self.end_headers()
                return note(self, 302, 0, t0)
            body = playlist(text, src).encode()
            self.send_response(up.status)
            self.send_header("Content-Type", "application/x-mpegURL")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if not head:
                self.wfile.write(body)
            note(self, up.status, len(body), t0)
            return
        self.send_response(up.status)
        for k in PASS:
            if up.headers.get(k):
                self.send_header(k, up.headers[k])
        if not up.headers.get("Content-Length"):
            self.send_header("Connection", "close")
        self.end_headers()
        if head:
            up.close()
            return note(self, up.status, 0, t0)
        try:
            shutil.copyfileobj(up, self.wfile, 256 * 1024)
        except OSError:
            self.close_connection = True  # TV seeked/closed, or VK reset mid-body: never reuse a desynced socket
        finally:
            up.close()
            note(self, up.status, -1, t0)

    def _plain(self, code, body):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass  # never log URLs: they carry the VK access token


if __name__ == "__main__":
    assert allowed("https://api.vk.com/method/x") and allowed("https://vkvd1.okcdn.ru/?a=1")
    assert target(PREFIX + "https:/api.vk.com/m?a=1") == "https://api.vk.com/m?a=1" == target(PREFIX + "https://api.vk.com/m?a=1")
    assert not allowed("https://evil.com/") and not allowed("https://okcdn.ru.evil.com/") and not allowed("http://api.vk.com/")
    m = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=852x480\n/a/480/\n#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1920x1080\n/a/1080/\n"
    assert playlist(m, "https://vkvd1.okcdn.ru/x/y.m3u8") == "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1920x1080\n" + PREFIX + "h/vkvd1.okcdn.ru/a/1080/\n"
    assert playlist("#EXTM3U\n#EXTINF:6,\nM0.ts\n#EXTINF:6,\n/a/M1.ts\n", "https://h.okcdn.ru/v/") == "#EXTM3U\n#EXTINF:6,\nM0.ts\n#EXTINF:6,\n" + PREFIX + "h/h.okcdn.ru/a/M1.ts\n"
    assert target(PREFIX + "h/h.okcdn.ru/v/M0.ts?a=1") == "https://h.okcdn.ru/v/M0.ts?a=1"
    assert best_variant(m, "https://vkvd1.okcdn.ru/x/y.m3u8") == "https://vkvd1.okcdn.ru/a/1080/"
    assert best_variant("#EXTM3U\n#EXTINF:6,\nM0.ts\n", "https://h/") is None
    http.server.ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8787"))), H).serve_forever()
