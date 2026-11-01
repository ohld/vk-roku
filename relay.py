#!/usr/bin/env python3
"""VK relay for the Roku VK app (Roku OS has no VPN). The TV requests
  GET /<KEY>/https://<vk host>/<path>?<query>
and this server fetches it from VK (fast path from a Hetzner box) and streams it back with Range support.
Only VK hosts are allowed and a secret KEY is required, so this is not an open proxy.
Env: RELAY_KEY (required), PORT (default 8787)."""
import http.server, os, shutil, urllib.error, urllib.parse, urllib.request

KEY = os.environ["RELAY_KEY"]
ALLOWED = ("vk.com", "vk.ru", "okcdn.ru", "mycdn.me", "userapi.com", "vkuser.net", "vkuservideo.net", "vkvideo.ru")
PASS = ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Last-Modified", "ETag")
UA = "VKAndroidApp/8.120-21460 (Android 13; SDK 33; arm64-v8a; Google Pixel; ru; 2400x1080)"
PREFIX = "/" + KEY + "/"


def target(path):
    """'/KEY/https://host/x' -> 'https://host/x'. Proxies may squash '//' into '/', so accept both."""
    rest = path[len(PREFIX):]
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


OPENER = urllib.request.build_opener(VKOnlyRedirects)


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 60  # idle keep-alive connections die instead of pinning threads

    def do_GET(self):
        if self.path == "/health":
            return self._plain(200, b"ok")
        url = target(self.path) if self.path.startswith(PREFIX) else ""
        if not allowed(url):
            return self._plain(404, b"not found")
        hdr = {"User-Agent": UA}
        if self.headers.get("Range"):
            hdr["Range"] = self.headers["Range"]
        try:
            up = OPENER.open(urllib.request.Request(url, headers=hdr), timeout=30)
        except urllib.error.HTTPError as e:
            up = e
        except Exception:
            return self._plain(502, b"upstream error")
        self.send_response(up.status)
        for k in PASS:
            if up.headers.get(k):
                self.send_header(k, up.headers[k])
        if not up.headers.get("Content-Length"):
            self.send_header("Connection", "close")
        self.end_headers()
        try:
            shutil.copyfileobj(up, self.wfile, 256 * 1024)
        except OSError:
            self.close_connection = True  # TV seeked/closed, or VK reset mid-body: never reuse a desynced socket
        finally:
            up.close()

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
    http.server.ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8787"))), H).serve_forever()
