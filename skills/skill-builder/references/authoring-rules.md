# Authoring rules for skills

## Contents
- Structure and naming
- Frontmatter
- Description formula
- Writing the body
- Progressive disclosure
- Lack of surprise
- Anti-patterns
- Pre-upload checklist

## Structure and naming

- Folder contains `SKILL.md` (exact case) and optionally `scripts/`, `references/`, `assets/`.
- No README.md inside the skill folder.
- Folder and `name` are kebab-case, no spaces, capitals, or underscores; the name matches the folder.
- Name max 64 characters, lowercase letters, numbers, hyphens only. Must not contain "claude" or "anthropic".
- Prefer gerund or clear action names (`processing-pdfs`, `sprint-planning`). Avoid vague names (`helper`, `utils`, `tools`).

## Frontmatter

Required:

```yaml
---
name: skill-name
description: What it does. Use when user says "phrase one", "phrase two".
---
```

Optional: `license` (MIT, Apache-2.0), `compatibility` (1 to 500 characters), `allowed-tools`, `metadata` (author, version, mcp-server, category, tags).

Only those six top-level keys are allowed; anything else goes under `metadata`. Long descriptions can use a YAML folded block (`description: >` followed by indented lines).

Forbidden: angle brackets in frontmatter, "claude"/"anthropic" in name, code in YAML. Frontmatter is injected into the system prompt, so keep it clean.

## Description formula

`[What it does] + [When to use it: concrete trigger phrases, file types] + [Key capabilities]`

- Under 1024 characters, third person ("Generates...", not "I can..." or "You can...").
- Include phrases users actually say, plus paraphrase variants and file types where relevant.
- Add negative triggers when neighbors exist: "Do NOT use for X (use Y instead)".
- Put every "when to use" detail here, not in the body: Claude sees only name and description when deciding to load the skill.
- Be slightly pushy. Claude tends to undertrigger, so name adjacent contexts: "Use whenever the user mentions dashboards or internal metrics, even if they don't say 'dashboard'."
- Claude consults skills mainly for multi-step or specialized work; a one-step request like "read this PDF" may not trigger any skill, so describe the substantive tasks.

| Quality | Example |
|---|---|
| Bad: vague | Helps with projects. |
| Bad: no trigger | Creates sophisticated multi-page documentation systems. |
| Bad: too technical | Implements the Project entity model with hierarchical relationships. |
| Good | Manages Linear sprint workflows including planning, task creation, and status tracking. Use when user mentions "sprint", "Linear tasks", or asks to "create tickets". |

Debug test once installed: ask Claude "When would you use the [skill] skill?" and adjust for what it omits.

## Writing the body

- Put critical instructions at the top under `## Critical rules` or `## Important`.
- Write in the imperative and explain why each rule matters. Repeated ALWAYS/NEVER in capitals is a yellow flag: a model that understands the reason handles cases the rule did not foresee.
- Generalize: write for the many future prompts, not just the examples you tested. Avoid overfitted special cases.
- Specific and actionable: exact commands, field names, expected output. Replace "validate the data" with the concrete checks.
- Define output formats with an exact template block when structure matters.
- Use numbered steps, bullets, short sentences. Do not explain what Claude already knows.
- Provide a default approach with an escape hatch, not a menu of options.
- Include error handling (cause and fix), at least 2 examples (user says, actions, result), and troubleshooting.
- For must-be-correct validations, bundle a script. Code is deterministic; language is not.
- Scripts: explicit error handling, specific messages, no unexplained constants, list required packages, state whether Claude should run or read the script.
- Name MCP tools fully (`ServerName:tool_name`) and verify names; they are case-sensitive.
- Consistent terminology; no time-sensitive facts outside a marked "old patterns" section; forward slashes only.

## Progressive disclosure

1. Frontmatter: always loaded, so it must decide triggering alone.
2. SKILL.md body: loaded when relevant. Under 500 lines and 5,000 words.
3. Linked files: loaded on demand. Link them directly from SKILL.md, one level deep (no doc-to-doc chains), with descriptive names and a note on when to read each. Files over 100 lines get a table of contents. Scripts can execute without being read, so nested script packages are fine.

Folder names: `scripts/`, `references/`, `assets/` are conventional. Anthropic's own skills also use folders such as `examples/` or `templates/`; any folder is fine if SKILL.md says what is in it and when to use it.

For multi-variant domains, use one reference per variant (`references/aws.md`, `references/gcp.md`) and let SKILL.md pick, so Claude loads only the relevant one.

## Lack of surprise

A skill's contents should match what a plain description of it would lead the user to expect. Do not build skills containing malware or exploit code, or skills designed for unauthorized access, data exfiltration, or deception. Role-play and persona skills are fine.

## Anti-patterns

- Vague description or missing triggers (undertriggering).
- Overbroad description (overtriggering); fix with negative triggers.
- Verbose or buried instructions (not followed).
- Ambiguous language ("make sure to validate things").
- Deep reference chains; Claude may only partially read nested files.
- Assuming packages are installed; assuming the skill is the only one loaded (skills must compose).
- Putting "be thorough" nudges in SKILL.md instead of the user prompt; they work better there, but a short Performance Notes section is acceptable.

## Pre-upload checklist

- [ ] 2 to 3 concrete use cases identified
- [ ] Folder kebab-case; `SKILL.md` exact spelling; `---` delimiters
- [ ] name valid; description has WHAT and WHEN; no angle brackets
- [ ] Instructions actionable; error handling; examples; references linked
- [ ] Triggers on obvious and paraphrased requests; silent on unrelated ones
- [ ] Functional tests pass; tool integration works (if applicable)
- [ ] Zipped for upload if distributing to Claude.ai
- [ ] After upload: monitor under/over-triggering, iterate, bump `metadata.version`
