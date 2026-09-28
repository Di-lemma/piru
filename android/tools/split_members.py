#!/usr/bin/env python3
"""Move named members of a type, doc comments included, into a `+SwiftUI.swift` companion.

    split_members.py <file.swift> <TypeName> <member> [<member>…]

Each member is cut from its leading `///` block through its brace-matched body and
re-emitted verbatim inside `extension <TypeName> { … }` in `<file>+SwiftUI.swift`, which
imports SwiftUI; a second run for another type appends to it. The source file keeps everything else; its `import SwiftUI` is left for
the caller to replace, because what the rest of the file needs is a separate question.
"""

import re
import sys
from pathlib import Path


def member_span(lines: list[str], name: str) -> tuple[int, int]:
    decl = re.compile(
        rf"^\s*(?:@\w+\s+)*(?:(?:static|private|fileprivate)\s+)*(?:var|func)\s+{name}\b"
    )
    start = next(i for i, line in enumerate(lines) if decl.match(line))
    doc = start
    while doc > 0 and lines[doc - 1].strip().startswith("///"):
        doc -= 1
    depth, end = 0, start
    for end in range(start, len(lines)):
        depth += lines[end].count("{") - lines[end].count("}")
        if depth == 0 and "{" in "".join(lines[start : end + 1]):
            break
    return doc, end


def main():
    path, type_name, *members = sys.argv[1:]
    src = Path(path)
    lines = src.read_text().split("\n")
    spans = sorted((member_span(lines, m) for m in members), reverse=True)
    moved = []
    for a, b in spans:
        block = lines[a : b + 1]
        while (
            a > 0
            and lines[a - 1].strip() == ""
            and (b + 1 < len(lines) and lines[b + 1].strip() == "")
        ):
            a -= 1
        moved.insert(0, block)
        del lines[a : b + 1]
    src.write_text("\n".join(lines))
    body = "\n\n".join("\n".join(block) for block in moved)
    companion = src.with_name(src.stem + "+SwiftUI.swift")
    # The extension carries the type's own isolation: under `-default-isolation MainActor` a
    # bare extension of a `nonisolated` type would make every moved member MainActor.
    name = re.escape(type_name)
    isolated = re.search(
        rf"^nonisolated\s+(?:(?:final\s+)?class|struct|enum|extension)\s+{name}(?![\w])",
        src.read_text(),
        re.M,
    )
    keyword = "nonisolated extension" if isolated else "extension"
    existing = companion.read_text() if companion.exists() else "import SwiftUI\n"
    companion.write_text(f"{existing}\n{keyword} {type_name} {{\n{body}\n}}\n")
    print(f"{src} → {companion.name}: moved {', '.join(members)}")


if __name__ == "__main__":
    main()
