"""Checks for bin/omabar-spotify. Run from the repository root:

    python3 -m unittest discover -s tests
"""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import time
import unittest
import urllib.error

sys.dont_write_bytecode = True
HELPER = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "bin", "omabar-spotify")


def load():
    loader = importlib.machinery.SourceFileLoader("omabar_spotify", HELPER)
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader("omabar_spotify", loader))
    loader.exec_module(module)
    return module


def http_error(code):
    return urllib.error.HTTPError("https://example.invalid", code, "error", {}, io.BytesIO(b"{}"))


class Links(unittest.TestCase):
    def test_links_and_uris(self):
        sp = load()
        self.assertEqual(sp.to_uri("spotify:playlist:0vvXsWCC9xrXsKd4FyS8kM"), "spotify:playlist:0vvXsWCC9xrXsKd4FyS8kM")
        self.assertEqual(sp.to_uri("spotify:user:someone:playlist:abc"), "spotify:playlist:abc")
        self.assertEqual(sp.to_uri(" https://open.spotify.com/intl-de/playlist/abc?si=1 "), "spotify:playlist:abc")
        self.assertEqual(sp.to_web("spotify:album:xyz"), "https://open.spotify.com/album/xyz")
        self.assertEqual(sp.to_web("spotify:collection:tracks"), "https://open.spotify.com/")
        with self.assertRaises(SystemExit):
            sp.to_uri("not a link")


class Playlists(unittest.TestCase):
    def setUp(self):
        self.sp = load()
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        for name in ("APP_FILE", "TOKEN_FILE", "CACHE_FILE"):
            setattr(self.sp, name, os.path.join(self.dir.name, name))
        self.sp.CACHE_DIR = self.dir.name
        self.calls = []

    def connect(self, expires_in=3600, **extra):
        self.sp.write_private(self.sp.APP_FILE, {"client_id": "a" * 32})
        self.sp.write_private(self.sp.TOKEN_FILE, dict(
            {"access_token": "old", "refresh_token": "keep", "expires_at": time.time() + expires_in}, **extra))

    def cache(self, age):
        self.sp.write_private(self.sp.CACHE_FILE, {"at": time.time() - age, "playlists": [{"name": "Saved", "uri": "spotify:playlist:s"}]})

    def answer(self, api):
        def api_request(url, data=None, headers=None):
            self.calls.append(url)
            return api(url, data, headers)
        self.sp.api_request = api_request
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(self.sp.cmd_playlists(), 0)
        return json.loads(out.getvalue())

    def page(self, url, data, headers):
        return {"items": [None, {"name": "Focus", "uri": "spotify:playlist:f", "owner": {"display_name": "Me"},
                                 "tracks": {"total": 3}, "images": [{"url": "big"}, {"url": "small"}]},
                          {"name": "No uri"}], "next": None}

    def test_not_connected(self):
        self.assertEqual(self.answer(self.page), {"connected": False, "error": "", "playlists": []})
        self.assertEqual(self.calls, [])

    def test_lists_playlists(self):
        self.connect()
        got = self.answer(self.page)
        self.assertEqual(got["playlists"], [{"name": "Focus", "uri": "spotify:playlist:f", "owner": "Me", "tracks": 3, "image": "small"}])
        self.assertEqual(self.answer(self.page)["playlists"], got["playlists"])
        self.assertEqual(len(self.calls), 1, "the second answer comes from the cache")

    def test_expired_token_is_refreshed(self):
        self.connect(expires_in=-10)

        def api(url, data, headers):
            if "api/token" in url:
                return {"access_token": "new", "expires_in": 3600}
            self.assertEqual(headers["Authorization"], "Bearer new")
            return self.page(url, data, headers)
        self.assertTrue(self.answer(api)["connected"])
        saved = self.sp.read_json(self.sp.TOKEN_FILE)
        self.assertEqual((saved["access_token"], saved["refresh_token"]), ("new", "keep"))

    def test_revoked_login_asks_to_reconnect_and_keeps_the_old_list(self):
        self.connect(expires_in=-10)
        self.cache(age=99999)

        def api(url, data, headers):
            raise http_error(400)
        got = self.answer(api)
        self.assertFalse(got["connected"])
        self.assertEqual(got["error"], self.sp.EXPIRED)
        self.assertEqual([p["name"] for p in got["playlists"]], ["Saved"])

    def test_token_rejected_early_is_refreshed_once(self):
        self.connect()

        def api(url, data, headers):
            if "api/token" in url:
                return {"access_token": "new", "expires_in": 3600}
            if headers["Authorization"] == "Bearer old":
                raise http_error(401)
            return self.page(url, data, headers)
        got = self.answer(api)
        self.assertTrue(got["connected"])
        self.assertEqual(len(got["playlists"]), 1)

    def test_offline_keeps_the_old_list_and_stays_connected(self):
        self.connect()
        self.cache(age=99999)

        def api(url, data, headers):
            raise urllib.error.URLError("no network")
        got = self.answer(api)
        self.assertTrue(got["connected"])
        self.assertTrue(got["error"])
        self.assertEqual([p["name"] for p in got["playlists"]], ["Saved"])

    def test_broken_token_file(self):
        self.sp.write_private(self.sp.APP_FILE, {"client_id": "a" * 32})
        self.sp.write_private(self.sp.TOKEN_FILE, {"access_token": "old"})
        self.assertEqual(self.answer(self.page)["connected"], False)
        with open(self.sp.TOKEN_FILE, "w") as handle:
            handle.write("[1, 2")
        self.assertEqual(self.answer(self.page)["connected"], False)


if __name__ == "__main__":
    unittest.main()
