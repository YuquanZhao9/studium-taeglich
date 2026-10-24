#!/usr/bin/env python3
"""Tiny sync store for the course player (marks + resume positions), run on the user's PC.

Listens on 127.0.0.1:8765 only; Tailscale exposes it to the user's own devices with
    tailscale serve --bg --set-path /sync http://127.0.0.1:8765
GET  .../sub/<path>.vtt -> subtitle next to a recording (.vtt, or .srt converted), read-only, under ROOT
GET  .../file/<path>     -> a recording under ROOT (video files only) with CORS, for offline download
GET  any other path  -> the whole store as JSON
POST any path  -> body {"marks": {id: {"at": ms, "items": [...]}}, "pos": {id: {"at": ms, ...}}};
                  per id the entry with the larger "at" wins; returns the merged store.
Data file: %LOCALAPPDATA%\\StudiumPlayer\\sync.json (outside the served lecture folder).
"""
import json, os, re, threading
from urllib.parse import unquote, urlsplit
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DIR = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"), "StudiumPlayer")
FILE = os.path.join(DIR, "sync.json")
LOCK = threading.Lock()
ORIGIN = "https://yuquanzhao9.github.io"
VIDEO = {".mp4", ".m4v", ".mov", ".webm", ".mkv"}
ROOT = os.path.realpath(os.environ.get("STUDIUM_ROOT") or r"F:\Stuttgart uni\Vorlesungen")


def load():
    try:
        with open(FILE, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        d = {}
    d.setdefault("marks", {}); d.setdefault("pos", {})
    return d


def save(d):
    os.makedirs(DIR, exist_ok=True)
    tmp = FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False)
    os.replace(tmp, FILE)


class H(BaseHTTPRequestHandler):
    def cors(self):
        o = self.headers.get("Origin")
        self.send_header("Access-Control-Allow-Origin", o if o in (ORIGIN, "http://localhost:8123") else ORIGIN)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Expose-Headers", "Content-Length")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Access-Control-Max-Age", "86400")
        self.send_header("Vary", "Origin")

    def reply(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code); self.cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_OPTIONS(self):
        self.send_response(204); self.cors(); self.send_header("Content-Length", "0"); self.end_headers()

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if "/sub/" in path:
            return self.subtitle(path.split("/sub/", 1)[1])
        if "/file/" in path:
            return self.file(path.split("/file/", 1)[1])
        with LOCK:
            self.reply(200, load())

    def file(self, rel):
        full = os.path.realpath(os.path.join(ROOT, rel))
        if not full.startswith(ROOT + os.sep) or os.path.splitext(full)[1].lower() not in VIDEO:
            return self.reply(403, {"error": "not allowed"})
        try:
            f = open(full, "rb")
        except OSError:
            return self.reply(404, {"error": "no file"})
        with f:
            size = os.fstat(f.fileno()).st_size
            self.send_response(200); self.cors()
            self.send_header("Content-Type", "video/mp4" if full.lower().endswith((".mp4", ".m4v")) else "application/octet-stream")
            self.send_header("Content-Length", str(size)); self.end_headers()
            try:
                while True:
                    b = f.read(1 << 20)
                    if not b: break
                    self.wfile.write(b)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def subtitle(self, rel):
        base = os.path.splitext(os.path.realpath(os.path.join(ROOT, rel)))[0]
        if not base.startswith(ROOT + os.sep):
            return self.reply(403, {"error": "outside"})
        text = None
        for ext in (".vtt", ".srt"):
            try:
                with open(base + ext, encoding="utf-8-sig") as f:
                    text = f.read()
                break
            except OSError:
                pass
        if text is None:
            return self.reply(404, {"error": "no subtitle"})
        if not text.lstrip().startswith("WEBVTT"):
            text = "WEBVTT\n\n" + re.sub(r"(\d\d:\d\d:\d\d),(\d\d\d)", r"\1.\2", text.replace("\r", ""))
        b = text.encode()
        self.send_response(200); self.cors()
        self.send_header("Content-Type", "text/vtt; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_POST(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if n > 5_000_000: return self.reply(413, {"error": "too large"})
            inc = json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return self.reply(400, {"error": "bad json"})
        with LOCK:
            d = load()
            for col in ("marks", "pos"):
                for k, v in (inc.get(col) or {}).items():
                    if isinstance(v, dict) and (k not in d[col] or (v.get("at") or 0) > (d[col][k].get("at") or 0)):
                        d[col][k] = v
            save(d)
            self.reply(200, d)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8765), H).serve_forever()
