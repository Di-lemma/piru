"""Copies one app source file with android/substitutions.txt applied, rule by rule, as
android/tools/stage.py's apply_substitutions does to the staged tree.

The tests build for macOS, where the Android modules the import rules name are absent, so
those imports go to the Compat stand-in with the same API (HOST_IMPORTS), and an import the
stage drops for an app stand-in stays (KEPT_IMPORTS).

Usage: stage_file.py <substitutions.txt> <input.swift> <output.swift>
"""

import re
import sys
from pathlib import Path

# Android module → the Compat stand-in with the API the file uses from it.
HOST_IMPORTS = {"SkipFuse": "os"}
# Imports the stage drops because an app stand-in provides their types; kept here.
KEPT_IMPORTS = ["CoreLocation"]


def main():
    substitutions, source, destination = (Path(arg) for arg in sys.argv[1:4])
    rules = []
    for line in substitutions.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        pattern, _, replacement = line.partition("\t")
        rules.append((re.compile(pattern, re.M), replacement))
    original = source.read_text()
    text = original
    for pattern, replacement in rules:
        text = pattern.sub(replacement, text)
    for android, host in HOST_IMPORTS.items():
        text = re.sub(rf"^([ \t]*)import {android}$", rf"\1import {host}", text, flags=re.M)
    for module in KEPT_IMPORTS:
        if re.search(rf"^import {module}$", original, re.M):
            text = f"import {module}\n" + text
    destination.write_text(text)


if __name__ == "__main__":
    main()
