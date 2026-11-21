#!/usr/bin/env python3
"""Scaffold a new skill folder from a category template.

Usage:
  python scaffold_skill.py --name my-skill --category workflow \
      --out ~/.claude/skills --description "Does X. Use when user says ..." \
      [--with scripts,references,assets] [--cases case-one,case-two] [--force]

Categories: document, workflow, mcp. Standard library only.
--cases writes test case folders under evals/ in the layout skill-creator and
`claude plugin eval` read, plus evals/trigger-queries.json, all with [TODO ...]
markers that the validator reports until they are filled.
"""
import argparse
import os
import re
import sys

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
MAX_NAME = 64

BODIES = {
    "document": """# {title}

## Critical rules

- [TODO: voice, forbidden content, required sections; give each rule a short reason]

## Instructions

### Step 1: Gather inputs
[TODO: what to collect from the user and what to infer]

### Step 2: Draft from the template
[TODO: point to assets/ template if used, and the section order]

### Step 3: Run the quality checklist
- [TODO: testable check 1]
- [TODO: testable check 2]

### Step 4: Finalize
[TODO: format, file name, where to save]

## Examples

**Example 1: [TODO common scenario]**
User says: "[TODO]"
Actions: [TODO]
Result: [TODO]

**Example 2: [TODO second scenario]**
User says: "[TODO]"
Actions: [TODO]
Result: [TODO]

## Troubleshooting

**[TODO common problem]**: Cause: [TODO]. Fix: [TODO].
""",
    "workflow": """# {title}

## Critical rules

- [TODO: ordering, validation gates, steps that must not be skipped; give each rule a short reason]

## Instructions

### Step 1: [TODO first step]
Action: [TODO]
Expected output: [TODO]
Validate: [TODO check before moving on]
On failure: [TODO recovery or rollback]

### Step 2: [TODO second step]
Action: [TODO, using output of Step 1]
Validate: [TODO]

### Step 3: Refinement loop (remove if not needed)
Quality criteria: [TODO]
Repeat fix and re-validate up to [TODO N] rounds, then finalize.

## Examples

**Example 1: [TODO common scenario]**
User says: "[TODO]"
Actions: [TODO]
Result: [TODO]

**Example 2: [TODO second scenario]**
User says: "[TODO]"
Actions: [TODO]
Result: [TODO]

## Troubleshooting

**[TODO common problem]**: Cause: [TODO]. Fix: [TODO].
""",
    "mcp": """# {title}

## Critical rules

- [TODO: preconditions to verify before calling any tool, such as required fields, and why]

## Prerequisites

- MCP server [TODO ServerName] is connected and authenticated.

## Instructions

### Step 1: [TODO first step]
Call `[TODO ServerName:tool_name]` with parameters [TODO].
Carry forward: [TODO ids or values needed by later steps].

### Step 2: [TODO second step]
Call `[TODO ServerName:tool_name]` using [TODO value from Step 1].
Validate: [TODO]

## Examples

**Example 1: [TODO common scenario]**
User says: "[TODO]"
Actions: [TODO]
Result: [TODO]

**Example 2: [TODO second scenario]**
User says: "[TODO]"
Actions: [TODO]
Result: [TODO]

## Troubleshooting

**MCP connection failed**: Verify the server shows as connected, the credentials are valid, and tool names match exactly (they are case-sensitive). Test the MCP directly without the skill to isolate the fault.
**[TODO domain-specific error]**: Cause: [TODO]. Fix: [TODO].
""",
}


CASE_RE = re.compile(r"^[a-z][a-z0-9-]*$")
RESERVED_CASES = {"results", "mocks", "node_modules", "files", "true", "false", "null"}

PROMPT_MD = """---
tags: [skill-builder]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

[TODO: the prompt exactly as a real user would type it, with realistic detail]
"""

CASE_YAML = """schema_version: "1.1"
name: {case}
expected_outcome: |
  [TODO: what a good result looks like]
"""

PLACEHOLDER_GRADER = """---
type: llm
focus: trace
weight: 1
---

The result matches this description: [TODO: the expected outcome]
"""

TRIGGER_QUERIES = """[
  {"query": "[TODO: realistic prompt that should load the skill]", "should_trigger": true},
  {"query": "[TODO: near-miss prompt that should not load it]", "should_trigger": false}
]
"""


def write_new(path, content):
    if os.path.exists(path):
        print(f"Kept existing {path}")
        return
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def scaffold_evals(root, cases):
    evals = os.path.join(root, "evals")
    for case in cases:
        d = os.path.join(evals, case)
        os.makedirs(os.path.join(d, "graders"), exist_ok=True)
        write_new(os.path.join(d, "prompt.md"), PROMPT_MD)
        write_new(os.path.join(d, "case.yaml"), CASE_YAML.format(case=case))
        write_new(os.path.join(d, "graders", "01-expected-output.md"), PLACEHOLDER_GRADER)
    os.makedirs(evals, exist_ok=True)
    write_new(os.path.join(evals, "trigger-queries.json"), TRIGGER_QUERIES)
    print(f"Created {len(cases)} test case folder(s) and trigger-queries.json under {evals}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--name", required=True)
    p.add_argument("--category", required=True, choices=sorted(BODIES))
    p.add_argument("--out", default="~/.claude/skills")
    p.add_argument("--description", default="[TODO: What it does. Use when user says \"phrase\".]")
    p.add_argument("--with", dest="extras", default="", help="comma list: scripts,references,assets")
    p.add_argument("--cases", default="", help="comma list of test case names (lowercase-with-hyphens)")
    p.add_argument("--force", action="store_true", help="overwrite an existing SKILL.md")
    a = p.parse_args()

    if not NAME_RE.match(a.name) or len(a.name) > MAX_NAME:
        sys.exit(f"ERROR: name must be kebab-case (lowercase, digits, hyphens), at most {MAX_NAME} characters.")
    if re.search(r"claude|anthropic", a.name):
        sys.exit("ERROR: name must not contain reserved words 'claude' or 'anthropic'.")
    if "<" in a.description or ">" in a.description:
        sys.exit("ERROR: description must not contain angle brackets.")

    extras = [e.strip() for e in a.extras.split(",") if e.strip()]
    bad = [e for e in extras if e not in ("scripts", "references", "assets")]
    if bad:
        sys.exit(f"ERROR: unknown --with values: {bad}")

    cases = [c.strip() for c in a.cases.split(",") if c.strip()]
    bad = [c for c in cases if not CASE_RE.match(c) or c in RESERVED_CASES]
    if bad:
        sys.exit(f"ERROR: bad case name(s) {bad}: lowercase letters, digits, hyphens, starting with a letter; "
                 f"not one of {sorted(RESERVED_CASES)}.")

    root = os.path.join(os.path.expanduser(a.out), a.name)
    skill_md = os.path.join(root, "SKILL.md")
    if os.path.exists(skill_md) and not a.force:
        if cases:  # add test cases to an existing skill without touching SKILL.md
            scaffold_evals(root, cases)
            return
        sys.exit(f"ERROR: {skill_md} exists. Use --force to overwrite.")
    os.makedirs(root, exist_ok=True)
    for e in extras:
        os.makedirs(os.path.join(root, e), exist_ok=True)

    desc = a.description.replace('"', "'")
    title = a.name.replace("-", " ").title()
    content = f'---\nname: {a.name}\ndescription: "{desc}"\nmetadata:\n  version: 0.1.0\n---\n\n' + BODIES[a.category].format(title=title)
    with open(skill_md, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)
    print(f"Created {skill_md}")
    if cases:
        scaffold_evals(root, cases)
    print("Next: fill every [TODO ...] marker, then run validate_skill.py on the folder.")


if __name__ == "__main__":
    main()
