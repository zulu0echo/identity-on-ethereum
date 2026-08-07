#!/usr/bin/env python3
"""P1 editorial pass: bring each specification into Internet-Draft section order.

Idempotent-ish structural transform applied to identity-stack/specs/*.md:
  1. RFC 2119 + RFC 8174 (BCP 14) boilerplate.
  2. Status of This Memo + Copyright Notice sections.
  3. IANA Considerations section (with a registry note where applicable).
  4. Abstract hygiene: no citations, links, or markup.
  5. References split into Normative / Informative.
  6. Section order: Abstract -> Status -> Copyright -> Conventions & Terminology
     (2119/8174 + relocated glossary) -> Introduction (was Motivation) -> body
     -> IANA Considerations -> Normative/Informative References.

Run: python3 site/apply-p1.py
"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
specs = sorted((root / "identity-stack" / "specs").glob("*.md"))

# Specs that will host an IANA registry (see the registry proposal). Others get
# a "no IANA actions" section.
REGISTRY_NOTE = {
    "01": ("Delegate Type registry",
           "the delegate-type values used here (`veriKey`, `sigAuth`), which ERC-1056 already employs"),
    "03": ("Capability Scope conventions registry",
           "the well-known capability-scope hashes an ecosystem agrees to share"),
    "06": ("Trust Role registry",
           "the role values `ROLE_ISSUER`, `ROLE_VERIFIER`, and `ROLE_ACCREDITOR`"),
    "08": ("Status Purpose registry",
           "the status-purpose values `Revocation` and `Suspension`, aligned with the W3C statusPurpose values"),
}

BCP14 = (
    'The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD\n'
    'NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as\n'
    "described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all\n"
    "capitals, as shown here."
)

# Normative = a standard an implementation is built against. Deliberately narrow:
# research papers and precedents (incl. RFC 6962, CT papers, ZCAP/UCAN, P3P) are
# informative, so nothing that must be implemented rests on a preprint (no bad downrefs).
NORMATIVE_TOKENS = [
    "rfc 2119", "rfc 8174", "rfc2119", "rfc8174", "bcp 14",
    "erc-1056", "bitstring status list", "semaphore: zero-knowledge",
    "verifiable credentials overview", "poseidon: a new hash",
    "on the size of pairing",
]

BCP14_REFS = [
    '[RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels", '
    "BCP 14, RFC 2119, March 1997 — https://www.rfc-editor.org/rfc/rfc2119",
    '[RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words", '
    "BCP 14, RFC 8174, May 2017 — https://www.rfc-editor.org/rfc/rfc8174",
]


def split_sections(body):
    """Return (title_line, [(heading, content_lines), ...]).
    Splits on top-level '# ' headings, honouring fenced code blocks."""
    lines = body.split("\n")
    title = None
    sections = []
    cur_head, cur_body = None, []
    in_fence = False
    for ln in lines:
        if ln.startswith("```"):
            in_fence = not in_fence
        is_h1 = (not in_fence) and re.match(r"^# (?!#)", ln)
        if is_h1:
            head = ln[2:].strip()
            if title is None and head.endswith("Specification"):
                title = ln
                continue
            if cur_head is not None:
                sections.append((cur_head, cur_body))
            cur_head, cur_body = head, []
        else:
            if cur_head is None:
                # preamble before first heading after title: ignore blanks
                if ln.strip() == "":
                    continue
                # stray content; attach to a synthetic head
                cur_head, cur_body = "_preamble", [ln]
            else:
                cur_body.append(ln)
    if cur_head is not None:
        sections.append((cur_head, cur_body))
    return title, sections


def decite(text):
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)   # [t](url) -> t
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)          # bold
    text = re.sub(r"(?<!\w)\*([^*]+)\*(?!\w)", r"\1", text)  # italic
    text = text.replace("`", "")                               # code ticks
    return text


def classify_refs(lines):
    normative, informative = [], []
    for ln in lines:
        s = ln.strip()
        if not s.startswith("- "):
            continue
        item = s[2:].strip()
        low = item.lower()
        if "rfc 2119" in low or "rfc2119" in low:  # replaced by BCP14 block
            continue
        if any(tok in low for tok in NORMATIVE_TOKENS):
            normative.append(item)
        else:
            informative.append(item)
    return normative, informative


def transform(path):
    slug = path.name[:2]
    raw = path.read_text(encoding="utf8")
    m = re.match(r"^(---\n[\s\S]*?\n---\n)", raw)
    front = m.group(1) if m else ""
    body = raw[len(front):]

    title, sections = split_sections(body)
    smap = {h: b for h, b in sections}

    def content(h):
        return "\n".join(smap.get(h, [])).strip("\n")

    # ---- Abstract (de-cited) ----
    abstract = decite(content("Abstract")).strip()

    # ---- Status of This Memo (absorbs Change Process) ----
    src = ""
    fm = re.search(r"^source:\s*(.+)$", front, re.M)
    if fm:
        src = fm.group(1).strip()
    status = (
        "This document is a working specification derived from a reference implementation. "
        "It is **not** an IETF document and has not been reviewed by any IETF working group; "
        "it is distributed for evaluation and discussion. It adopts IETF conventions — BCP 14 "
        "requirement keywords, Security and Privacy Considerations, an IANA Considerations "
        "section, and split references — so that institutional reviewers can read it against "
        "familiar structure, but it claims no IETF status.\n\n"
        "Changes are made by pull request against the source repository. The reference "
        "implementation" + (f" in `{src}`" if src else "") + " and its test suite are "
        "normative where this prose is ambiguous."
    )

    copyright = (
        "This specification is published under the MIT license of the repository that contains "
        "it (see `LICENSE`). Contributors retain copyright in their contributions and license "
        "them under those terms. A formal IETF submission would instead be governed by the IETF "
        "Trust's Legal Provisions (BCP 78) and the rights described in BCP 79; this notice is "
        "provided in their place for a non-IETF document."
    )

    # ---- Conventions & Terminology (BCP14 + relocated glossary) ----
    conventions = BCP14
    gloss = content("Glossary")
    if gloss:
        conventions += "\n\n## Terminology\n\n" + gloss

    # ---- Introduction (was Motivation) ----
    introduction = content("Motivation")

    # ---- IANA Considerations ----
    if slug in REGISTRY_NOTE:
        name, what = REGISTRY_NOTE[slug]
        iana = (
            "This document is not currently on the IETF stream and requests no IANA actions at "
            "this time.\n\n"
            f"Were it submitted, it would establish a **{name}**, replacing the enumeration that "
            f"is presently defined inline — namely {what}. A companion registry proposal specifies "
            "the registry's contents, allocation policy (Specification Required or Expert Review), "
            "and initial entries; until that proposal is adopted these values are defined in this "
            "document and are not IANA-managed."
        )
    else:
        iana = "This document requests no IANA actions."

    # ---- References (split) ----
    ref_lines = smap.get("References", [])
    normative, informative = classify_refs(ref_lines)
    normative = BCP14_REFS + normative

    def refblock(items):
        return "\n".join("- " + it for it in items) if items else "None."

    # ---- middle sections in original order, minus the ones we relocate ----
    handled = {"Abstract", "Change Process", "Language", "Motivation",
               "References", "Glossary", "IANA Considerations",
               "Status of This Memo", "Copyright Notice",
               "Conventions and Terminology", "_preamble"}
    middle = []
    for h, b in sections:
        if h in handled:
            continue
        middle.append("# " + h + "\n\n" + "\n".join(b).strip("\n"))

    out = []
    out.append(front.rstrip("\n"))
    out.append("")
    out.append(title if title else "# Specification")
    out.append("")
    out.append("# Abstract\n\n" + abstract)
    out.append("# Status of This Memo\n\n" + status)
    out.append("# Copyright Notice\n\n" + copyright)
    out.append("# Conventions and Terminology\n\n" + conventions)
    out.append("# Introduction\n\n" + introduction)
    out.extend(middle)
    out.append("# IANA Considerations\n\n" + iana)
    out.append("# Normative References\n\n" + refblock(normative))
    out.append("# Informative References\n\n" + refblock(informative))

    doc = "\n\n".join(s for s in out if s is not None)
    doc = re.sub(r"\n{3,}", "\n\n", doc).rstrip("\n") + "\n"
    path.write_text(doc, encoding="utf8")
    return slug, len(normative), len(informative), bool(gloss)


rows = [transform(p) for p in specs]
print("slug  norm  info  gloss-moved")
for slug, n, i, g in rows:
    print(f"  {slug}    {n:>2}    {i:>2}    {g}")
print(f"transformed {len(rows)} specs")
