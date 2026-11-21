"""Checks for bin/omabar-setup's layout program. From the repository root:

    python3 -m unittest discover -s tests
"""
import os
import re
import unittest

SETUP = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "bin", "omabar-setup")


class SetupLayoutTest(unittest.TestCase):
    def test_layout_program_has_no_stray_quote(self):
        # The layout jq program sits in one single-quoted shell string, so an
        # apostrophe anywhere in it (even in a comment) ends the string early
        # and jq fails with "unexpected end of file".
        text = open(SETUP, encoding="utf-8").read()
        match = re.search(r"--argjson worldClockSaved \"\$world_clock_saved\" '\n(.*?)\n' \"\$source_file\" >\"\$tmp\"", text, re.S)
        self.assertIsNotNone(match, "couldn't find the layout program")
        self.assertNotIn("'", match.group(1))
        self.assertIn('"omabar-battery"', match.group(1))


if __name__ == "__main__":
    unittest.main()
