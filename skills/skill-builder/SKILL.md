---
name: skill-builder
description: Rapidly builds new, validated Claude skills (SKILL.md plus optional scripts, references, assets) from a short interview, using templates for document and asset creation, workflow automation, and MCP enhancement, writes test cases that skill-creator and claude plugin eval can run, validates, packages, and hands off to testing. Use whenever the user wants to create, draft, scaffold, or template a new skill, says "build a skill", "make a skill that", "create a skill for", "turn this workflow into a skill", "save this as a skill", or "/skill-builder", even if they only describe a repeatable task they want Claude to do the same way every time. Do NOT use for improving, benchmarking, or re-tuning an existing skill (use skill-creator for that).
license: MIT
compatibility: Claude Code or Claude.ai with code execution. Scripts run with Python 3 (standard library only) or, where Python is missing, Windows PowerShell 5.1 or PowerShell 7.
metadata:
  version: 1.2.0
  source: The Complete Guide to Building Skills for Claude; Anthropic best-practices docs; anthropics/skills examples
---

# Skill Builder

Build an effective, spec-compliant skill in one sitting: capture intent, scaffold from a category template, write it and its tests, validate with the script, package it, and run the tests. Building stays here; the test loop hands off to skill-creator when it is installed, so this skill stays small.

## Critical rules

- **Interview before writing.** A skill written from a guessed goal triggers on the wrong requests, and fixing it later costs more than one more question now.
- **Validate before presenting.** Run `scripts/validate_skill.py` (or `scripts/validate_skill.ps1`) and fix every ERROR. It checks the hard rules (name, description, frontmatter keys, angle brackets) that make an upload fail or a skill never trigger.
- **Keep docs inside the skill.** Never put README.md in the skill folder; documentation belongs in SKILL.md or linked files.
- **Build only what the user would expect.** Never build a skill whose behavior would surprise the user if described plainly, or one meant for unauthorized access, data exfiltration, or deception.

## Instructions

### Step 1: Capture intent (5 to 10 questions, cap 10)

If the conversation already shows the workflow ("turn this into a skill"), extract the answers from it first: tools used, step order, corrections the user made, input and output formats. Then ask only about gaps. Use AskUserQuestion with 2 to 4 options and a recommended default when choices are enumerable; batch up to 4 independent questions. Cover, in priority order:

1. **Goal and output**: what task, and what a finished run produces.
2. **Category**: document/asset creation, workflow automation, or MCP enhancement. Recommend one; see `references/category-templates.md`.
3. **Triggers**: 3 to 5 things a user would actually type, plus near-miss requests that should NOT trigger it.
4. **Steps and decisions**: the ordered workflow, branch points, and validation gates.
5. **Tools**: built-in only, bundled scripts, or which MCP servers and exact tool names.
6. **Domain rules**: style guides, compliance rules, templates, terminology to embed.
7. **Failure modes**: common errors and the fix for each.
8. **Name and location**: kebab-case name; default `~/.claude/skills/`, alternatives project `.claude/skills/` or a staging folder; whether to zip for Claude.ai.

Stop asking once nothing material is ambiguous, and state remaining assumptions.

### Step 2: Pick the pattern

Map the category to a pattern in `references/category-templates.md` (sequential workflow, multi-MCP coordination, iterative refinement, context-aware tool selection, domain-specific intelligence). Combining two is fine. If the skill covers several variants (for example AWS, GCP, Azure), plan one reference file per variant so Claude reads only the relevant one.

### Step 3: Scaffold

Every script comes in two versions with the same checks and output: Python (`.py`) and PowerShell (`.ps1`). Use Python when `python` or `python3` runs; otherwise use the PowerShell version, which Windows always has. The commands below are Python; the PowerShell form of each is in Troubleshooting.

```bash
python scripts/scaffold_skill.py --name my-skill --category workflow --out ~/.claude/skills --description "Does X. Use when the user ..." --cases typical-case,edge-case
```

Categories: `document`, `workflow`, `mcp`. Add `--with scripts,references,assets` for bundled folders. `--cases` adds test case folders and `evals/trigger-queries.json`. Existing skills are not overwritten without `--force`. The output contains `[TODO ...]` markers to fill.

### Step 4: Write the skill

Fill every `[TODO ...]` marker following `references/authoring-rules.md`. The essentials:

- **Description carries all "when to use" info**, because only the name and description are visible when Claude decides whether to load the skill. Formula: what it does + when to use it (real phrases, contexts, file types) + key capabilities. Third person, under 1024 characters, no angle brackets. Make it slightly pushy ("Use whenever ..., even if the user doesn't say X"), since Claude tends to undertrigger. Add "Do NOT use for ..." when a neighboring skill overlaps.
- **Body**: imperative instructions, critical rules at the top, and a short reason behind each rule rather than ALL-CAPS commands. Be concrete: exact commands, fields, expected output.
- **Size**: body under 500 lines; move detail into reference files linked directly from SKILL.md, with a note on when to read each.
- **Include**: error handling, at least 2 examples (user says, actions, result), and troubleshooting.
- **Deterministic checks**: if a validation must never be wrong, or every run would rewrite the same helper, bundle a script.
- Consistent terminology; no time-sensitive facts; forward slashes in paths; MCP tools as `ServerName:tool_name`.

Then reread the draft fresh and cut anything that is not pulling its weight.

### Step 5: Write the tests

Fill the test case folders and `evals/trigger-queries.json` following `references/test-plan.md`: 2 to 3 realistic cases with one checkable statement per grader file, and 8 to 10 should-trigger plus 8 to 10 near-miss should-NOT-trigger queries. Use invented data only, because tests ship with the skill.

### Step 6: Validate and package

```bash
python scripts/validate_skill.py ~/.claude/skills/my-skill
```

Fix all ERRORs and re-run until the last line reads `RESULT: PASS`. It checks the test folders too, since a malformed case silently fails to load later. Treat WARNs as judgment calls, not failures. If the user wants a Claude.ai upload:

```bash
python scripts/package_skill.py ~/.claude/skills/my-skill
```

### Step 7: Run the tests and hand off

Ask the user for the review mode (automated grading or viewer review), recommending one by output type as `references/test-plan.md` describes. Then run the tests with the first available option from its "Running the tests" section: hand off to skill-creator if installed, else offer `claude plugin eval`, else run the cases inline. Present the file tree, final description, validator result, test results, and install path. The packager leaves `evals/` out of the zip.

## Examples

**Example 1: workflow from the current conversation**
User says: "that invoice reconciliation we just did, turn it into a skill"
Actions: extract steps, tools, and corrections from the conversation → ask only about triggers and location → scaffold with `--category mcp --cases ...` → fill skill and tests → validate → hand off to skill-creator with automated grading.
Result: `reconciling-invoices/` passing validation and its tests, with triggers matching how the user phrased the request.

**Example 2: document skill from scratch**
User says: "I need a skill so every blog post follows our style guide"
Actions: interview (style rules, template sections, checklist) → scaffold with `--category document --with assets,references --cases ...` → put the template in `assets/` and the style guide in `references/` → validate → review outputs in the viewer (subjective output) → package as zip.
Result: skill with an embedded style guide, output template, and a pre-finalize quality checklist, ready to upload.

## Troubleshooting

**Validator: no trigger condition**: add a "Use when the user ..." clause with real phrases.
**Validator: unexpected frontmatter key**: only name, description, license, allowed-tools, metadata, and compatibility are allowed (Claude Code-only keys such as `when_to_use` only warn, since a Claude.ai upload rejects them); move custom fields under `metadata`.
**Skill would overtrigger**: add "Do NOT use for ..." naming the neighboring skill, and narrow the nouns.
**Skill won't upload**: the file must be exactly `SKILL.md`, the frontmatter needs both `---` delimiters, and the name must be kebab-case and match the folder.
**Installed skill ignores instructions**: shorten the body, move critical rules to the top, explain why each matters, replace vague wording with concrete checks, or bundle a script.
**Validator: case fails to load**: keep `schema_version: "1.1"` quoted, make `name` match the folder, keep at least one file in `graders/`, and allow only the scaffolded keys in prompt.md's settings block.
**skill-creator not found**: offer `/plugin install skill-creator@claude-plugins-official`, or use the fallbacks in `references/test-plan.md`.
**Python not found**: try `python3`; otherwise run the PowerShell versions. `-ExecutionPolicy Bypass` is needed because Windows blocks unsigned scripts by default, and it applies to that one command only. On macOS or Linux, use `pwsh` in place of `powershell`.
```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/scaffold_skill.ps1 -Name my-skill -Category workflow -Out ~/.claude/skills -Description "Does X. Use when the user ..." -Cases typical-case,edge-case
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate_skill.ps1 ~/.claude/skills/my-skill
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package_skill.ps1 ~/.claude/skills/my-skill
```
If neither runs, check manually against `references/authoring-rules.md`.
