#!/usr/bin/env python3
"""Validate a skill folder against the Claude skill-building guide.

Usage: python validate_skill.py PATH_TO_SKILL_FOLDER
Exit code 0 = PASS (warnings allowed), 1 = FAIL (one or more errors).
Standard library only (no PyYAML needed).

Errors mirror hard rules (Anthropic's quick_validate.py plus the guide's
MUST rules). Warnings are guide recommendations; Anthropic's own published
skills skip some of them, so treat warnings as judgment calls.
"""
import json
import os
import re
import sys

MAX_NAME = 64          # spec limit for name
MAX_DESC = 1024        # spec limit for description
MAX_COMPAT = 500       # spec limit for compatibility
MAX_BODY_LINES = 500   # best-practice guidance for SKILL.md body
MAX_BODY_WORDS = 5000  # guide: keep SKILL.md under 5,000 words
TOC_LINES = 100        # best-practice: longer reference docs need a contents list
ALLOWED_KEYS = {"name", "description", "license", "allowed-tools", "metadata", "compatibility"}
# Keys Claude Code reads but a Claude.ai upload rejects: warn instead of fail.
CLAUDE_CODE_KEYS = {"when_to_use", "argument-hint", "arguments", "disable-model-invocation", "user-invocable",
                    "model", "effort", "context", "agent", "hooks", "paths", "shell"}
CASE_RE = re.compile(r"^[a-z][a-z0-9-]*$")
EVAL_SKIP_DIRS = {"results", "mocks", "node_modules", "files"}
PROMPT_KEYS = {"tags", "max_turns", "timeout_seconds", "allowed_tools"}
MIN_TRIGGER = 8        # per side, for description tuning
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TRIGGER_RE = re.compile(
    r"\b(use (it |this |this skill )?(when|whenever|for|if)|trigger|whenever|when (the )?users?\b|if the user)", re.I)
FIRST_PERSON_RE = re.compile(r"\b(I can|I will|I help|you can use|you can|helps you|you should)\b", re.I)
BLOCK_SCALAR = re.compile(r"^[>|][+-]?$")
CODE_RE = re.compile(r"```.*?```|`[^`\n]*`", re.S)
DOC_EXT = (".md", ".txt")

errors, warns = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warns.append(msg)


def unquote(val):
    if len(val) >= 2 and val[0] == val[-1] == '"':
        return val[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    if len(val) >= 2 and val[0] == val[-1] == "'":
        return val[1:-1].replace("''", "'")
    return val


def parse_frontmatter(text):
    """Return (dict, body) or (None, text).

    Handles top-level scalars, quoted strings, folded (>) and literal (|)
    block scalars, and nested mappings (kept as raw text).
    """
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != "---":
        return None, text
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return None, text
    fm, i, body_lines = {}, 1, lines[1:end]
    i = 0
    while i < len(body_lines):
        line = body_lines[i]
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2).strip()
        block = []
        i += 1
        while i < len(body_lines) and (body_lines[i].startswith((" ", "\t")) or not body_lines[i].strip()):
            block.append(body_lines[i].strip())
            i += 1
        while block and not block[-1]:
            block.pop()
        if BLOCK_SCALAR.match(val):
            fm[key] = ("\n" if val[0] == "|" else " ").join(block).strip()
        elif val:
            joined = " ".join([val] + [b for b in block if b])  # plain multi-line scalar
            fm[key] = unquote(joined.strip())
        else:
            fm[key] = {"_raw": "\n".join(block)}  # nested mapping such as metadata
    return fm, "\n".join(lines[end + 1:])


def main(path):
    path = os.path.abspath(os.path.expanduser(path))
    if not os.path.isdir(path):
        print(f"ERROR: not a directory: {path}")
        return 1
    folder = os.path.basename(path)
    entries = os.listdir(path)

    if "SKILL.md" not in entries:
        near = [e for e in entries if e.lower() == "skill.md"]
        err(f"SKILL.md missing; found {near[0]!r}. Rename to exactly SKILL.md." if near
            else "SKILL.md missing in skill folder.")
        return report()
    if any(e.lower() == "readme.md" for e in entries):
        err("README.md present in skill folder. Move content to SKILL.md or references/.")
    nested = []
    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if d not in ("__pycache__", "node_modules", "evals") and not d.startswith(".")]
        if root != path and "SKILL.md" in files:
            nested.append(os.path.relpath(os.path.join(root, "SKILL.md"), path).replace(os.sep, "/"))
    if nested:
        err(f"Nested SKILL.md file(s): {', '.join(nested)}. Uploads reject more than one; rename supporting docs.")
    if not NAME_RE.match(folder):
        err(f"Folder name {folder!r} must be kebab-case (lowercase, digits, single hyphens).")

    with open(os.path.join(path, "SKILL.md"), encoding="utf-8") as f:
        text = f.read()
    fm, body = parse_frontmatter(text)
    if fm is None:
        err("Frontmatter missing or unclosed: file must start with --- and close with ---.")
        return report()

    cc_only = sorted(set(fm) & CLAUDE_CODE_KEYS)
    if cc_only:
        warn(f"Frontmatter key(s) {', '.join(cc_only)} work in Claude Code but a Claude.ai upload rejects them.")
    unexpected = sorted(set(fm) - ALLOWED_KEYS - CLAUDE_CODE_KEYS)
    if unexpected:
        err(f"Unexpected frontmatter key(s): {', '.join(unexpected)}. Allowed: {', '.join(sorted(ALLOWED_KEYS))}. "
            "Put custom fields under metadata.")

    # angle brackets in any frontmatter value (block-scalar indicators are not values)
    for k, v in fm.items():
        s = v["_raw"] if isinstance(v, dict) else v
        if "<" in s or ">" in s:
            err(f"Frontmatter field {k!r} contains angle brackets (< or >), which are forbidden.")

    # name
    name = fm.get("name", "")
    if not isinstance(name, str) or not name:
        err("Frontmatter: name is required (a string).")
    else:
        if not NAME_RE.match(name):
            err(f"name {name!r} must be kebab-case: lowercase letters, digits, single hyphens; no spaces or capitals.")
        if len(name) > MAX_NAME:
            err(f"name is {len(name)} characters; max {MAX_NAME}.")
        if re.search(r"claude|anthropic", name, re.I):
            err("name must not contain reserved words 'claude' or 'anthropic'.")
        if name != folder:
            err(f"name {name!r} should match folder name {folder!r}.")

    # description
    desc = fm.get("description", "")
    if not isinstance(desc, str) or not desc:
        err("Frontmatter: description is required and non-empty.")
    else:
        if len(desc) > MAX_DESC:
            err(f"description is {len(desc)} characters; max {MAX_DESC}.")
        if not TRIGGER_RE.search(desc):
            err("description has no trigger condition. Add 'Use when the user ...' with concrete phrases or contexts.")
        if len(desc) < 100:
            warn("description is short; Claude tends to undertrigger, so add contexts, phrases, and file types.")
        if FIRST_PERSON_RE.search(desc):
            warn("description should be third person (avoid 'I can', 'you can', 'helps you').")
        if '"' not in desc and "'" not in desc and "“" not in desc:
            warn("description has no quoted user phrases; real phrases users type improve triggering.")

    compat = fm.get("compatibility", "")
    if isinstance(compat, str) and compat and len(compat) > MAX_COMPAT:
        err(f"compatibility must be at most {MAX_COMPAT} characters (is {len(compat)}).")

    # body
    no_code = CODE_RE.sub("", body)
    body_lines = body.strip().splitlines()
    words = len(body.split())
    if len(body_lines) > MAX_BODY_LINES:
        warn(f"SKILL.md body is {len(body_lines)} lines; aim for under {MAX_BODY_LINES}. Move detail to linked files.")
    if words > MAX_BODY_WORDS:
        warn(f"SKILL.md body is {words} words; keep under {MAX_BODY_WORDS}. Move detail to linked files.")
    if re.search(r"\[TODO", no_code, re.I) or (isinstance(desc, str) and "[TODO" in desc):
        err("Unfilled [TODO ...] markers remain.")
    if not re.search(r"^#{1,4}\s+.*example", body, re.I | re.M):
        warn("No Examples section; the guide recommends at least 2 (user says, actions, result).")
    if not re.search(r"^#{1,4}\s+.*(troubleshoot|common issues|error|if something fails|failure)", body, re.I | re.M):
        warn("No Troubleshooting or error-handling section.")
    if re.search(r"</?[A-Za-z][A-Za-z0-9_-]*(\s[^>\n]*)?>", no_code):
        warn("Body contains XML-like tags outside code spans; prefer Markdown.")
    if re.search(r"\b[\w.-]+\\[\w.-]+\\?", no_code):
        warn("Possible Windows backslash path; use forward slashes.")

    # bundled files: docs must be reachable from SKILL.md (no hidden chains)
    linked_text = body
    unreferenced_docs, long_docs, unreferenced_dirs = [], [], []
    for e in sorted(entries):
        full = os.path.join(path, e)
        if e.startswith(".") or e in ("__pycache__", "evals"):
            continue
        if os.path.isdir(full):
            if e not in linked_text:
                unreferenced_dirs.append(e + "/")
            for root, dirs, files in os.walk(full):
                dirs[:] = [d for d in dirs if d not in ("__pycache__", "node_modules")]
                for fn in files:
                    rel = os.path.relpath(os.path.join(root, fn), path).replace(os.sep, "/")
                    if fn.lower().endswith(DOC_EXT) and fn != "LICENSE.txt":
                        if rel not in linked_text and fn not in linked_text:
                            unreferenced_docs.append(rel)
                        with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as rf:
                            content = rf.read()
                        if fn.endswith(".md") and len(content.splitlines()) > TOC_LINES and not re.search(
                                r"^#+\s*(table of )?contents", content, re.I | re.M):
                            long_docs.append(rel)
    if unreferenced_dirs:
        warn(f"Folder(s) never mentioned in SKILL.md: {', '.join(unreferenced_dirs)}. Claude will not know they exist.")
    if unreferenced_docs:
        warn(f"Doc file(s) not linked directly from SKILL.md (keep references one level deep): {', '.join(unreferenced_docs[:8])}"
             + (" ..." if len(unreferenced_docs) > 8 else ""))
    if long_docs:
        warn(f"Doc file(s) over {TOC_LINES} lines without a Contents section: {', '.join(long_docs)}")
    # Check paths in prose and inline code spans (where skills usually write them),
    # but not fenced blocks, which often hold example commands with placeholder paths.
    no_fences = re.sub(r"```.*?```", "", body, flags=re.S)
    for ref in sorted(set(re.findall(r"\b((?:references|scripts|assets)/[\w./-]*\w)", no_fences))):
        if "*" not in ref and not os.path.exists(os.path.join(path, ref)):
            err(f"SKILL.md links {ref} but it does not exist. Create it or remove the reference.")

    check_evals(os.path.join(path, "evals"))
    return report()


def check_evals(evals):
    """Check test cases against the layout skill-creator and `claude plugin eval` read."""
    if not os.path.isdir(evals):
        warn("No evals/ folder. Add test cases (scaffold_skill.py --cases) so the skill can be tested.")
        return
    cases = []
    for e in sorted(os.listdir(evals)):
        d = os.path.join(evals, e)
        if not os.path.isdir(d) or e in EVAL_SKIP_DIRS or e.startswith("."):
            continue
        if not (os.path.exists(os.path.join(d, "prompt.md")) or os.path.exists(os.path.join(d, "case.yaml"))):
            continue
        cases.append(e)
        tag = f"evals/{e}"
        if not CASE_RE.match(e) or e in ("true", "false", "null"):
            err(f"{tag}: case name must be lowercase letters, digits, hyphens, starting with a letter.")
        for fn in ("prompt.md", "case.yaml"):
            if not os.path.exists(os.path.join(d, fn)):
                err(f"{tag}: {fn} missing.")
        pm = os.path.join(d, "prompt.md")
        if os.path.exists(pm):
            with open(pm, encoding="utf-8") as f:
                ptext = f.read()
            pfm, pbody = parse_frontmatter(ptext)
            if ptext.lstrip().startswith("---") and pfm is None:
                err(f"{tag}/prompt.md: settings block is not closed with ---.")
            if pfm:
                extra = sorted(set(pfm) - PROMPT_KEYS)
                if extra:
                    err(f"{tag}/prompt.md: unknown setting(s) {', '.join(extra)} make the case fail to load.")
            if not (pbody if pfm is not None else ptext).strip():
                err(f"{tag}/prompt.md: no prompt text after the settings block.")
        cy = os.path.join(d, "case.yaml")
        if os.path.exists(cy):
            with open(cy, encoding="utf-8") as f:
                ytext = f.read()
            if not re.search(r"^schema_version:\s*[\"']1\.1[\"']\s*$", ytext, re.M):
                err(f"{tag}/case.yaml: needs schema_version: \"1.1\" (quoted, or it reads as a number).")
            m = re.search(r"^name:\s*[\"']?([^\"'\n]+?)[\"']?\s*$", ytext, re.M)
            if not m or m.group(1) != e:
                err(f"{tag}/case.yaml: name must equal the folder name {e!r}.")
        gdir = os.path.join(d, "graders")
        graders = [g for g in sorted(os.listdir(gdir)) if g.endswith(".md")] if os.path.isdir(gdir) else []
        if not graders:
            err(f"{tag}: no graders/*.md; a case with no grader fails to load (keep the placeholder until real ones exist).")
        for g in graders:
            with open(os.path.join(gdir, g), encoding="utf-8") as f:
                gfm, _ = parse_frontmatter(f.read())
            if not gfm or "type" not in gfm:
                err(f"{tag}/graders/{g}: needs a settings block with type (the CLI ignores it otherwise).")
        for root, _, files in os.walk(d):
            for fn in files:
                if fn.endswith((".md", ".yaml")):
                    with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as f:
                        if "[TODO" in f.read():
                            err(f"{tag}: unfilled [TODO ...] marker in {os.path.relpath(os.path.join(root, fn), d).replace(os.sep, '/')}.")
    if not cases:
        if os.path.exists(os.path.join(evals, "evals.json")):
            warn("Only evals/evals.json (older format). Add case folders; skill-creator and claude plugin eval run those.")
        else:
            warn("evals/ has no test case folders (each needs prompt.md, case.yaml, graders/).")
    elif len(cases) < 2:
        warn(f"Only {len(cases)} test case; 2 to 3 realistic cases give a more useful signal.")

    tq = os.path.join(evals, "trigger-queries.json")
    if not os.path.exists(tq):
        warn("No evals/trigger-queries.json; description tuning needs should and should-not trigger queries.")
        return
    try:
        with open(tq, encoding="utf-8") as f:
            items = json.load(f)
    except (ValueError, OSError) as ex:
        err(f"evals/trigger-queries.json is not valid JSON: {ex}")
        return
    if not isinstance(items, list) or not all(
            isinstance(i, dict) and isinstance(i.get("query"), str) and isinstance(i.get("should_trigger"), bool)
            for i in items):
        err('evals/trigger-queries.json must be a list of {"query": "...", "should_trigger": true|false}.')
        return
    if any("[TODO" in i["query"] for i in items):
        err("evals/trigger-queries.json: unfilled [TODO ...] queries.")
    pos = sum(i["should_trigger"] for i in items)
    neg = len(items) - pos
    if pos < MIN_TRIGGER or neg < MIN_TRIGGER:
        warn(f"trigger-queries.json has {pos} should-trigger and {neg} should-not; aim for {MIN_TRIGGER} to 10 of each.")


def report():
    for w in warns:
        print("WARN:  " + w)
    for e in errors:
        print("ERROR: " + e)
    print(f"RESULT: {'FAIL' if errors else 'PASS'} ({len(errors)} errors, {len(warns)} warnings)")
    return 1 if errors else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
