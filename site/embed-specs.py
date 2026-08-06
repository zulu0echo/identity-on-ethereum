#!/usr/bin/env python3
"""Embed the markdown of identity-stack/specs/*.md into site/specs.html.

The annex page is self-contained (no runtime fetches), so the spec texts are
inlined as a JS object between two marker comments. Run this after editing any
specification to refresh the page:

    python3 site/embed-specs.py
"""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
specs_dir = root / "identity-stack" / "specs"
page = root / "site" / "specs.html"

texts = {}
for f in sorted(specs_dir.glob("*.md")):
    texts[f.name] = f.read_text(encoding="utf8")

blob = ("/* SPEC_MD_START */\n  var SPEC_MD = "
        + json.dumps(texts, ensure_ascii=False, indent=0)
        + ";\n  /* SPEC_MD_END */")

src = page.read_text(encoding="utf8")
pat = re.compile(r"/\* SPEC_MD_START \*/[\s\S]*?/\* SPEC_MD_END \*/")
if not pat.search(src):
    sys.exit("markers not found in specs.html")
page.write_text(pat.sub(lambda _: blob, src), encoding="utf8")
print(f"embedded {len(texts)} specs, {sum(len(t) for t in texts.values())} chars")
