"""Checks bin/omabar-mail-unread: it reads Thunderbird's unread counts from
Mork .msf summaries (inline and by-reference cells, last one wins) and says
whether Thunderbird is there at all. From the repository root:

    python3 -m unittest discover -s tests
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..")
HELPER = os.path.join(ROOT, "bin", "omabar-mail-unread")


class MailUnreadTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.home)
        # A PATH without thunderbird, so "installed" comes from the profile alone.
        self.path = os.path.join(self.home, "bin")
        os.makedirs(self.path)

    def inbox(self, account, text):
        folder = os.path.join(self.home, ".thunderbird", "abc.default", "ImapMail", account)
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "INBOX.msf"), "w", encoding="latin-1") as handle:
            handle.write(text)

    def run_helper(self):
        env = dict(os.environ, HOME=self.home, PATH=self.path)
        result = subprocess.run([sys.executable, HELPER], env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_no_thunderbird(self):
        data = self.run_helper()
        self.assertEqual(data["unread"], 0)
        self.assertFalse(data["installed"])

    def test_counts_every_inbox(self):
        # Inline cells: the later transaction (hex C = 12) overrides the first.
        self.inbox("imap.one.com", "<(9F=numNewMsgs)>\n[1(^9F=3)]\n@$${2{@[1(^9F=C)]@$$}2}@\n")
        # A cell that points at a value atom.
        self.inbox("imap.two.com", "<(9F=numNewMsgs)>\n<(A1=2)>\n[1(^9F^A1)]\n")
        data = self.run_helper()
        self.assertTrue(data["installed"])
        self.assertEqual(data["unread"], 14)
        self.assertEqual(sorted(i["account"] for i in data["inboxes"]), ["imap.one.com", "imap.two.com"])

    def test_profile_without_inboxes_is_still_installed(self):
        os.makedirs(os.path.join(self.home, ".thunderbird"))
        data = self.run_helper()
        self.assertTrue(data["installed"])
        self.assertEqual(data["inboxes"], [])


if __name__ == "__main__":
    unittest.main()
