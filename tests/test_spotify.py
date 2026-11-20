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


class LikedSongs(unittest.TestCase):
    """cmd_liked against a stand-in Spotify."""

    def setUp(self):
        self.sp = sp = load()
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        sp.CACHE_DIR = self.dir.name
        sp.time.sleep = lambda seconds: None
        self.status, self.track, self.sent, self.told = "Paused", "a", [], []
        self.plays = set()          # the URIs this Spotify actually starts
        sp.ensure_running = lambda: False
        sp.spotify_running = lambda: True
        sp.playback_status = lambda: self.status
        sp.track_id = lambda: self.track
        sp.set_shuffle = lambda on: self.sent.append(("shuffle", on)) or True
        sp.notify = self.told.append
        self.web, self.asked = "login", []
        sp.web_play_liked = lambda shuffle: self.web
        sp.ask_for_playback = lambda shuffle: self.asked.append(shuffle) or True

        def open_uri(uri):
            self.sent.append(uri)
            if uri in self.plays:
                self.status, self.track = "Playing", "liked"
            return True
        sp.open_uri = open_uri

    def test_shuffle_goes_on_before_the_songs_start(self):
        self.plays = {"spotify:collection:tracks"}
        self.assertEqual(self.sp.cmd_liked(), 0)
        self.assertEqual(self.sent, [("shuffle", True), "spotify:collection:tracks"])
        self.assertEqual(self.told, [])

    def test_no_shuffle(self):
        self.plays = {"spotify:collection:tracks"}
        self.assertEqual(self.sp.cmd_liked(shuffle=False), 0)
        self.assertEqual(self.sent, ["spotify:collection:tracks"])

    def test_tries_the_other_name(self):
        self.plays = {"spotify:collection"}
        self.assertEqual(self.sp.cmd_liked(), 0)
        self.assertEqual(self.sent[1:], ["spotify:collection:tracks", "spotify:collection"])

    def test_account_starts_them_without_touching_the_app(self):
        self.web = "ok"
        self.assertEqual(self.sp.cmd_liked(), 0)
        self.assertEqual((self.sent, self.told, self.asked), ([], [], []))

    def test_page_only_asks_once_for_playback_access(self):
        self.status = "Playing"     # Spotify only shows the page and keeps playing
        self.assertEqual(self.sp.cmd_liked(), 1)
        self.assertEqual((self.asked, self.told), ([True], []))

    def test_after_the_approval_it_does_not_ask_again(self):
        self.assertEqual(self.sp.cmd_liked(may_ask=False), 1)
        self.assertEqual(self.asked, [])
        self.assertEqual(len(self.told), 1)

    def test_premium_is_named(self):
        self.web = "premium"
        self.assertEqual(self.sp.cmd_liked(), 1)
        self.assertEqual(self.asked, [])
        self.assertIn("Premium", self.told[0])


class LikedSongsWebApi(unittest.TestCase):
    def setUp(self):
        self.sp = sp = load()
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        sp.TOKEN_FILE = os.path.join(self.dir.name, "token")
        sp.APP_FILE = os.path.join(self.dir.name, "app")
        sp.time.sleep = lambda seconds: None
        sp.write_private(sp.APP_FILE, {"client_id": "a" * 32})
        self.sends = []
        self.refuse = {}            # path fragment -> HTTP code
        self.reason = "{}"

        def api_request(url, data=None, headers=None):
            if url.endswith("/me"):
                return {"id": "cory"}
            if "devices" in url:
                return {"devices": [{"id": "phone", "type": "Smartphone"}, {"id": "t480", "type": "Computer"}]}
            if "/me/tracks" in url:
                return {"total": 2, "items": [{"track": {"uri": "spotify:track:1"}}, {"track": {"uri": "spotify:track:2"}},
                                              {"track": None}, {"track": {"uri": "spotify:local:x"}}]}
            self.fail("unexpected " + url)
        sp.api_request = api_request

        def api_send(method, url, token, body=None):
            for fragment, code in self.refuse.items():
                if fragment in url and (fragment != "/play" or "context_uri" in (body or {})):
                    raise urllib.error.HTTPError(url, code, "no", {}, io.BytesIO(self.reason.encode()))
            self.sends.append((method, url.split("/v1/me/player/")[1].split("?")[0], body))
            return True
        sp.api_send = api_send

    def login(self, scope):
        self.sp.write_private(self.sp.TOKEN_FILE, {"access_token": "t", "refresh_token": "r",
                                                   "expires_at": time.time() + 999, "scope": scope})

    def test_needs_a_login_with_playback_access(self):
        self.login("playlist-read-private")
        self.sp.api_request = lambda *a, **k: self.fail("must not call Spotify without playback access")
        self.assertEqual(self.sp.web_play_liked(True), "login")

    def test_plays_the_whole_library_on_this_computer_with_shuffle(self):
        self.login(self.sp.SCOPES)
        self.assertEqual(self.sp.web_play_liked(True), "ok")
        self.assertEqual(self.sends[:2], [("PUT", "shuffle", None),
                                          ("PUT", "play", {"context_uri": "spotify:user:cory:collection"})])

    def test_without_shuffle_only_play_is_sent(self):
        self.login(self.sp.SCOPES)
        self.assertEqual(self.sp.web_play_liked(False), "ok")
        self.assertEqual(self.sends, [("PUT", "play", {"context_uri": "spotify:user:cory:collection"})])

    def test_sends_the_songs_when_the_library_as_a_whole_is_refused(self):
        self.login(self.sp.SCOPES)
        self.refuse = {"/play": 400}
        self.assertEqual(self.sp.web_play_liked(False), "ok")
        self.assertEqual(self.sends, [("PUT", "play", {"uris": ["spotify:track:1", "spotify:track:2"]})])

    def test_premium_required(self):
        self.login(self.sp.SCOPES)
        self.refuse, self.reason = {"/play": 403, "/shuffle": 403}, '{"error": {"reason": "PREMIUM_REQUIRED"}}'
        self.assertEqual(self.sp.web_play_liked(True), "premium")


if __name__ == "__main__":
    unittest.main()
