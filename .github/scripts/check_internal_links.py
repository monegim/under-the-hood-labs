#!/usr/bin/env python3
"""Fail if any relative markdown link points at a file that doesn't exist.
External (http/https/mailto) links are skipped — those are checked
separately, if at all, since network checks are flaky in CI.
"""
import re
import sys
import pathlib

link_re = re.compile(r"\]\(([^)]+)\)")


def main() -> int:
    failed = False
    for md in pathlib.Path(".").rglob("*.md"):
        if ".git" in md.parts:
            continue
        text = md.read_text(errors="ignore")
        for m in link_re.finditer(text):
            target = m.group(1).split("#")[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            resolved = (md.parent / target).resolve()
            if not resolved.exists():
                print(f"::error file={md}::broken relative link: {target}")
                failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
