#!/usr/bin/env python3
"""Validate the static capability-gallery resource inventory.

This is intentionally a structural check. It does not parse the full authored
language and it makes no claim about Slate construction, layout, or runtime input.
"""

from __future__ import annotations

import argparse
import collections
import io
import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path


REQUIRED_PAGES = ("layout", "forms", "data", "collections", "commands", "composition")
RESOURCE_SUFFIXES = {".html", ".xml"}
BINDING_SUFFIX = re.compile(r"(?:-bind|^bind$|^action$|^event$)", re.IGNORECASE)


class InventoryParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tags: collections.Counter[str] = collections.Counter()
        self.classes: collections.Counter[str] = collections.Counter()
        self.bindings: collections.Counter[str] = collections.Counter()
        self.ids: list[tuple[str, str]] = []
        self.tab_keys: collections.Counter[str] = collections.Counter()
        self.template_depth = 0
        self.element_stack: list[tuple[str, str | None]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        attributes = {name.lower(): value for name, value in attrs}
        parent = self.element_stack[-1] if self.element_stack else None
        self.tags[tag] += 1
        if tag == "template":
            self.template_depth += 1
        for name, value in attrs:
            if value is None:
                continue
            lowered = name.lower()
            if lowered == "class":
                self.classes.update(value.split())
            elif lowered == "id":
                # Menu declarations are named lookup tables, not runtime widget IDs.
                if self.template_depth == 0 and tag != "menu":
                    self.ids.append((value, tag))
            if BINDING_SUFFIX.search(lowered) or lowered.endswith("-binding"):
                self.bindings[name] += 1
            if tag == "tab" and parent == ("tabs", "gallery-pages") and lowered == "key":
                self.tab_keys[value] += 1
        self.element_stack.append((tag, attributes.get("id")))

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        for index in range(len(self.element_stack) - 1, -1, -1):
            if self.element_stack[index][0] == tag:
                removed = self.element_stack[index:]
                del self.element_stack[index:]
                self.template_depth = max(0, self.template_depth - sum(item[0] == "template" for item in removed))
                return

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)


def parse_text(text: str) -> InventoryParser:
    parser = InventoryParser()
    try:
        events = ET.iterparse(io.StringIO(text), events=("start", "end"))
        for event, element in events:
            if event == "start":
                parser.handle_starttag(element.tag, [(str(key), value) for key, value in element.attrib.items()])
            else:
                parser.handle_endtag(element.tag)
    except ET.ParseError:
        parser = InventoryParser()
        parser.feed(text)
        parser.close()
    return parser


def parse_file(path: Path) -> InventoryParser:
    return parse_text(path.read_text(encoding="utf-8-sig"))


def duplicate_ids(parser: InventoryParser) -> list[str]:
    """Report duplicate IDs within a resource file, allowing template scopes.

    Authored templates are reusable definitions, so duplicate IDs inside a
    template are not treated as global collisions. Runtime instances are scoped
    by the retained view and are outside this static check.
    """
    counts = collections.Counter(value for value, _ in parser.ids)
    return sorted(value for value, count in counts.items() if count > 1)


def main() -> int:
    argument_parser = argparse.ArgumentParser(description=__doc__)
    argument_parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).parent)
    argument_parser.add_argument("--standalone", action="store_true", help="validate a copyable resource without the gallery page inventory")
    args = argument_parser.parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        print(f"error: resource directory does not exist: {root}", file=sys.stderr)
        return 2

    files = sorted(path for path in root.rglob("*") if path.is_file() and path.suffix.lower() in RESOURCE_SUFFIXES)
    if not files:
        print(f"error: no XML resources found under {root}", file=sys.stderr)
        return 2

    tags: collections.Counter[str] = collections.Counter()
    classes: collections.Counter[str] = collections.Counter()
    bindings: collections.Counter[str] = collections.Counter()
    failures: list[str] = []
    for path in files:
        parser = parse_file(path)
        tags.update(parser.tags)
        classes.update(parser.classes)
        bindings.update(parser.bindings)
        for duplicate in duplicate_ids(parser):
            failures.append(f"{path.relative_to(root)}: duplicate id outside explicit runtime scope: {duplicate}")

    gallery_path = root / "CapabilityGallery.ui.html"
    if not gallery_path.is_file():
        gallery_tabs: collections.Counter[str] = collections.Counter()
        if not args.standalone:
            failures.append("missing gallery document: CapabilityGallery.ui.html")
    else:
        gallery_tabs = parse_file(gallery_path).tab_keys
    if gallery_path.is_file():
        missing = [page for page in REQUIRED_PAGES if page not in gallery_tabs]
        if missing:
            failures.append("missing required page keys: " + ", ".join(missing))
        unexpected = sorted(set(gallery_tabs) - set(REQUIRED_PAGES))
        if unexpected:
            failures.append("unexpected gallery tab keys: " + ", ".join(unexpected))
        duplicate_tabs = sorted(page for page, count in gallery_tabs.items() if count != 1)
        if duplicate_tabs:
            failures.append("gallery tab keys must appear exactly once: " + ", ".join(duplicate_tabs))

    print(f"resources={len(files)}")
    print("pages=" + ",".join(sorted(gallery_tabs)))
    print("tags=" + ",".join(f"{name}:{count}" for name, count in sorted(tags.items())))
    print("classes=" + ",".join(f"{name}:{count}" for name, count in sorted(classes.items())))
    print("bindings=" + ",".join(f"{name}:{count}" for name, count in sorted(bindings.items())))
    if failures:
        for failure in failures:
            print("ERROR " + failure, file=sys.stderr)
        return 1
    print("static gallery inventory: PASS (structural only; runtime behavior not verified)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
