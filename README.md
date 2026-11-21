# claude-skill-builder

A Claude Code plugin with one skill, `skill-builder`, that builds new Claude skills in one sitting. It interviews you, scaffolds from a template, writes the skill and its test cases, validates, and packages it.

## Install

```
/plugin marketplace add steven-llamas/claude-skill-builder
/plugin install skill-builder@skill-builder
```

Then say "build a skill that ..." or run `/skill-builder:skill-builder`.

Claude.ai: zip `skills/skill-builder/` and upload it under Settings > Capabilities > Skills.

## Testing built skills (optional)

Tests are written in the layout that both of these read:

- [skill-creator](https://github.com/anthropics/skills): `/plugin install skill-creator@claude-plugins-official`. skill-builder hands off to it when it is installed.
- `claude plugin eval` (Claude Code 2.1.269 or later).

## Requirements

Python 3 (standard library only), or PowerShell where Python is missing: Windows PowerShell 5.1 ships with Windows, and PowerShell 7 (`pwsh`) runs on macOS and Linux.

## License

MIT. The test case layout follows Anthropic's skill-creator (Apache-2.0).
