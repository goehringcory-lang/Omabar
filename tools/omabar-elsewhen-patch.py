#!/usr/bin/env python3
"""Give a clone of Omarchy's world clock (Elsewhen) split-flap times.

    tools/omabar-elsewhen-patch.py <clone dir> <omabar modules dir>

Copies OmabarFlapText.qml into the clone and swaps each city's big time for a
row of flap tiles in the theme's accent color. Safe to run again: a clone
that is already patched is left alone. If Elsewhen has changed so the edit no
longer matches, nothing is written and the clone keeps working unpatched.
"""
import pathlib
import shutil
import sys

OLD = """      Text {
        id: bigTime
        textFormat: Text.PlainText
        text: row.ready ? row.rowData.time : "--:--"
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.heading
        font.weight: Font.DemiBold
      }
"""

NEW = """      // Omabar: split-flap digits in the accent color.
      OmabarFlapText {
        id: bigTime
        text: row.ready ? row.rowData.time : "--:--"
        tileHeight: Math.round(Style.font.heading * 1.55)
        accent: Commons.Color.accent
        base: Commons.Color.background
        fontName: row.fontFamily
        stagger: 45
      }
"""

MARK = "// Omabar: split-flap digits"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    clone = pathlib.Path(sys.argv[1])
    modules = pathlib.Path(sys.argv[2])
    row = clone / "CityRow.qml"
    text = row.read_text(encoding="utf-8")
    shutil.copyfile(modules / "OmabarFlapText.qml", clone / "OmabarFlapText.qml")
    if MARK in text:
        print("omabar: world clock already has split-flap times")
        return 0
    if text.count(OLD) != 1:
        print("omabar: the world clock has changed; left it unstyled", file=sys.stderr)
        return 1
    row.write_text(text.replace(OLD, NEW), encoding="utf-8")
    print("omabar: world clock now uses split-flap times")
    return 0


if __name__ == "__main__":
    sys.exit(main())
