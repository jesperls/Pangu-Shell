import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

SHELL = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("link_preview", SHELL / "scripts/link_preview.py")
lp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lp)


def _fake_addrinfo(host_map):
    def _lookup(host, port, *args, **kwargs):
        ips = host_map.get(host, [])
        return [(0, 0, 0, "", (ip, 0)) for ip in ips]
    return _lookup


class _FakeResponse:
    def __init__(self, body: bytes, url: str, content_type: str):
        self._buf = io.BytesIO(body)
        self._url = url
        self.headers = {"Content-Type": content_type}

    def geturl(self):
        return self._url

    def read(self, n=-1):
        return self._buf.read(n)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class LinkPreviewTest(unittest.TestCase):
    def test_resolves_public_rejects_empty_and_private_ips(self):
        host_map = {
            "empty.test": [],
            "loop.test": ["127.0.0.1"],
            "lan.test": ["192.168.1.5"],
            "v6mapped.test": ["::ffff:127.0.0.1"],
            "mixed.test": ["93.184.216.34", "10.0.0.2"],
            "public.test": ["93.184.216.34"],
        }
        with patch.object(lp.socket, "getaddrinfo", side_effect=_fake_addrinfo(host_map)):
            self.assertFalse(lp._resolves_public("empty.test"))
            self.assertFalse(lp._resolves_public("loop.test"))
            self.assertFalse(lp._resolves_public("lan.test"))
            self.assertFalse(lp._resolves_public("v6mapped.test"))
            self.assertFalse(lp._resolves_public("mixed.test"))
            self.assertTrue(lp._resolves_public("public.test"))

    def test_safe_http_asset_blocks_private_hosts_and_bad_schemes(self):
        host_map = {
            "example.com": ["93.184.216.34"],
            "internal.lan": ["10.0.0.1"],
            "localhost": ["127.0.0.1"],
        }
        with patch.object(lp.socket, "getaddrinfo", side_effect=_fake_addrinfo(host_map)):
            self.assertEqual(lp._safe_http_asset("http://127.0.0.1/secret.png", "https://example.com/"), "")
            self.assertEqual(lp._safe_http_asset("https://internal.lan/img.png", "https://example.com/"), "")
            self.assertEqual(lp._safe_http_asset("file:///etc/passwd", "https://example.com/"), "")
            self.assertEqual(lp._safe_http_asset("javascript:alert(1)", "https://example.com/"), "")
            self.assertEqual(
                lp._safe_http_asset("/static/card.png", "https://example.com/post"),
                "https://example.com/static/card.png",
            )

    def test_meta_parser_handles_valueless_link_type_and_svg_titles(self):
        html = """
        <html>
          <head>
            <link rel="icon" href="/fav.png" type>
            <title>Real Page Title</title>
          </head>
          <body>
            <svg><title>SVG Icon Label</title></svg>
          </body>
        </html>
        """
        parser = lp.MetaTagParser()
        parser.feed(html)
        self.assertEqual(parser.metadata["title"], "Real Page Title")
        self.assertEqual(parser.get_best_favicon(), "/fav.png")

    def test_meta_parser_ignores_svg_title_before_head_title(self):
        html = "<html><body><svg><title>Icon</title></svg></body><head><title>Doc Title</title></head></html>"
        parser = lp.MetaTagParser()
        parser.feed(html)
        self.assertEqual(parser.metadata["title"], "Doc Title")

    def test_fetch_preview_accepts_xhtml_and_filters_private_assets(self):
        body = (
            b'<html><head><title>XHTML Doc</title>'
            b'<meta property="og:image" content="http://127.0.0.1/private.png">'
            b'<link rel="icon" href="https://example.com/icon.svg">'
            b'</head><body></body></html>'
        )
        host_map = {
            "example.com": ["93.184.216.34"],
            "127.0.0.1": ["127.0.0.1"],
        }

        class _FakeOpener:
            def open(self, req, timeout=5):
                return _FakeResponse(body, "https://example.com/page", "APPLICATION/XHTML+XML; charset=utf-8")

        with patch.object(lp.socket, "getaddrinfo", side_effect=_fake_addrinfo(host_map)), \
             patch.object(lp.urllib.request, "build_opener", return_value=_FakeOpener()):
            result = lp.fetch_preview("https://example.com/page")

        self.assertEqual(result["title"], "XHTML Doc")
        self.assertEqual(result["image"], "")
        self.assertEqual(result["favicon"], "https://example.com/icon.svg")

    def test_youtube_metadata_keeps_oembed_thumbnail_verbatim(self):
        payload = json.dumps({
            "title": "Demo Video",
            "author_name": "Author",
            "thumbnail_url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
        }).encode("utf-8")
        with patch.object(
            lp.urllib.request,
            "urlopen",
            return_value=_FakeResponse(payload, "https://www.youtube.com/oembed", "application/json"),
        ):
            result = lp.fetch_youtube_metadata("https://youtu.be/dQw4w9WgXcQ")
        self.assertEqual(result["image"], "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")


if __name__ == "__main__":
    unittest.main()
