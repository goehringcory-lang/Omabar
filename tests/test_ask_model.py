"""Checks for modules/OmabarAskModel.js (run through node). From the
repository root:

    python3 -m unittest discover -s tests
"""
import json
import os
import shutil
import subprocess
import unittest
from urllib.parse import unquote

MODEL = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "modules", "OmabarAskModel.js")
NODE = shutil.which("node")


def call(fn, *args):
    script = "const m = require(%s); process.stdout.write(JSON.stringify(m[%s](...%s)))" % (
        json.dumps(MODEL), json.dumps(fn), json.dumps(list(args)))
    out = subprocess.run([NODE, "-e", script], check=True, capture_output=True, text=True).stdout
    return json.loads(out) if out else None


@unittest.skipUnless(NODE, "node is not installed")
class AskModelTest(unittest.TestCase):
    def test_claude_link_carries_the_question_intact(self):
        q = "What's 2 + 2? & why #math\nsecond line"
        plan = call("plan", "claude", "  " + q + "  ")
        self.assertTrue(plan["url"].startswith("https://claude.ai/new?q="))
        self.assertFalse(plan["copy"])
        self.assertEqual(unquote(plan["url"].split("?q=", 1)[1]), q)
        # Nothing that would end the query or start a fragment survives raw.
        self.assertNotIn("&", plan["url"].split("?q=", 1)[1])
        self.assertNotIn("#", plan["url"])

    def test_gemini_goes_through_the_clipboard(self):
        plan = call("plan", "gemini", "hello")
        self.assertTrue(plan["copy"])
        self.assertEqual(plan["url"], "https://gemini.google.com/app")

    def test_grok_link_and_agents_use_clipboard(self):
        self.assertTrue(call("plan", "grok", "hi")["url"].startswith("https://grok.com/?q="))
        for agent in ("duet", "dot"):
            self.assertTrue(call("plan", agent, "hi")["copy"])

    def test_links_setting_picks_the_page(self):
        plan = call("plan", "duet", "hi", {"duet": "https://claude.ai/duet"})
        self.assertEqual(plan["url"], "https://claude.ai/duet")
        self.assertTrue(plan["copy"])
        # Only https links are taken.
        self.assertEqual(call("plan", "duet", "hi", {"duet": "javascript:alert(1)"})["url"], "https://claude.ai/")

    def test_long_question_falls_back_to_clipboard(self):
        plan = call("plan", "chatgpt", "word " * 3000)
        self.assertTrue(plan["copy"])
        self.assertEqual(plan["url"], "https://chatgpt.com/")

    def test_empty_question_asks_nothing(self):
        self.assertIsNone(call("plan", "claude", "   \n "))

    def test_unknown_provider_falls_back_to_first(self):
        self.assertEqual(call("provider", "nope")["id"], "claude")

    def test_shown_follows_setting_order_and_ignores_unknown(self):
        ids = [p["id"] for p in call("shown", ["Gemini", "bogus", "claude", "gemini"])]
        self.assertEqual(ids, ["gemini", "claude"])
        self.assertEqual([p["id"] for p in call("shown", [])], ["claude", "chatgpt", "gemini", "grok", "duet", "dot"])

    def test_history_newest_first_without_repeats(self):
        h = call("remember", ["b", "a"], " a ", 20)
        self.assertEqual(h, ["a", "b"])
        self.assertEqual(len(call("remember", [str(i) for i in range(30)], "new", 20)), 20)


if __name__ == "__main__":
    unittest.main()
