#!/usr/bin/env python3
"""Turn an edit to upstream sources into a patch in android/patches, and append it to series.

    mkpatch.py <name> <upstream-path>... [--message "why"]

Edit the files in the repo checkout, run this, then restore them (git checkout -- <paths>):
the patch is taken from `git diff` of exactly those paths, so it applies to the pristine tree
that stage.py copies. The first line of the patch file is the reason, for whoever rebases it.
"""

import argparse
import subprocess
import sys
from pathlib import Path

ANDROID = Path(__file__).resolve().parents[1]
REPO = ANDROID.parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--message", required=True)
    args = parser.parse_args()
    diff = subprocess.run(
        ["git", "diff", "--", *args.paths], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout
    if not diff:
        sys.exit("no changes in those paths")
    series = ANDROID / "patches" / "series"
    existing = [
        line
        for line in series.read_text().splitlines()
        if line.strip() and not line.startswith("#")
    ]
    number = max((int(line.split("-", 1)[0]) for line in existing), default=0) + 1
    name = f"{number:04d}-{args.name}.patch"
    (ANDROID / "patches" / name).write_text(f"{args.message}\n\n{diff}")
    with series.open("a") as f:
        f.write(name + "\n")
    print(f"android/patches/{name}")


if __name__ == "__main__":
    main()
