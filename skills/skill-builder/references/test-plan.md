# Test plan

Write the tests in the layout below. skill-creator and `claude plugin eval` both read it as is, so the tests never need converting.

## Contents
- Writing good test prompts
- Test case folders
- Trigger queries
- Choosing the review mode
- Running the tests
- Iteration signals

## Writing good test prompts

- Make them realistic: what a user would actually type, with detail such as file names, column names, company context, casual phrasing, even typos.
  - Weak: "Format this data"
  - Strong: "my boss sent Q4 sales final v2.xlsx, can you add a profit margin % column, revenue is col C and costs col D i think"
- Make them substantive. Claude skips skills for trivial one-step requests, so a simple prompt can fail to trigger even with a perfect description.
- Use invented data only. Test files ship with the skill's repo, so never paste real customer records, personal data, or internal system names into a prompt or input file.

## Test case folders

Create them with `scripts/scaffold_skill.py --cases name-one,name-two` or `scripts/scaffold_skill.ps1 -Cases name-one,name-two` (both also work on an existing skill). Write 2 to 3 cases: one typical, one edge case, and one that needs a branch or decision in the workflow.

```
evals/
├── flags-negative-quantity/     # case name: lowercase-with-hyphens, says what is tested
│   ├── prompt.md                # settings block, then the user's prompt
│   ├── case.yaml                # schema_version "1.1", name, expected_outcome
│   ├── graders/01-....md        # one checkable statement per file
│   └── files/                   # input files, only if the test needs any
└── trigger-queries.json
```

- **prompt.md**: keep the scaffolded settings block (`tags`, `max_turns`, `timeout_seconds`, `allowed_tools` are the only keys allowed). The prompt goes after the closing `---`. Free text never goes in the settings block.
- **case.yaml**: `schema_version: "1.1"` stays quoted; `name` equals the folder; `expected_outcome` is a plain-language description of success.
- **graders**: one statement per file, numbered (`01-states-total.md`, `02-flags-bad-row.md`), each with the scaffolded `type: llm` block on top. Word each one about the result ("summary.md states a total revenue of 693.5"), not about where outputs are saved. For subjective output (tone, design), keep the placeholder grader and judge by eye instead.
- **Input files**: put them in `files/`, end the prompt with `Input files: a.csv, b.txt`, add a `place-files.sh` next to prompt.md containing `cp -R "$(dirname "$0")/files/." .`, and add `context:` / `scaffold_script: place-files.sh` to case.yaml.

## Trigger queries

`evals/trigger-queries.json` is a plain JSON list, the format skill-creator's description tuner reads:

```json
[
  {"query": "realistic prompt", "should_trigger": true},
  {"query": "near-miss prompt", "should_trigger": false}
]
```

- 8 to 10 should-trigger: different phrasings (formal, casual), at least one that never names the topic, one where this skill competes with a neighbor and should win.
- 8 to 10 should-NOT-trigger near misses: shared keywords but a different need, or a request a neighboring skill should handle. "Write a fibonacci function" tests nothing for a PDF skill.

## Choosing the review mode

Ask the user once per skill, recommending by output type:

| Output | Recommend | Why |
|---|---|---|
| Objectively checkable (file transforms, extracted data, fixed workflow steps, code) | Automated grading | Graders decide pass or fail; no human pass needed, fewer tokens |
| Subjective (writing style, design, tone) | Viewer review | Only a person can judge it; graders would be forced |

## Running the tests

Use the first option that is available:

1. **skill-creator is installed** (a skill named `skill-creator`, or `anthropic-skills:skill-creator`): invoke it with the Skill tool and pass this, filled in:
   `The skill at PATH is already drafted and validated. Its tests are in evals/ (case folders) and evals/trigger-queries.json. Skip capturing intent, interviewing, and drafting: go straight to running and evaluating the test cases with baselines. Review mode: viewer | automated grading only (skip the browser viewer and summarize results in chat). Afterward, offer description optimization using evals/trigger-queries.json.`
   Install it with `/plugin install skill-creator@claude-plugins-official` if the user wants it.
2. **Claude Code without skill-creator**: offer `claude plugin eval . --allow-tools Write,Edit,Bash` from the skill folder (add `--scaffold` if a case has input files, `--max-cost-usd N` for a budget). It runs every case with and without the skill. These are real billed runs, so ask before starting.
3. **Claude.ai or no CLI**: for each case, read the skill and do the prompt yourself, one at a time, then show the prompt and output and ask for feedback. Skip baselines.

## Iteration signals

- Undertriggering (never loads, users enable it manually): add contexts, phrases, and technical keywords; make the description pushier.
- Overtriggering (loads for unrelated queries): add negative triggers and narrow the scope.
- Execution problems (inconsistent output, user corrections): tighten instructions, explain the why, add error handling, bundle a script.
- Repeated work: if every test run writes the same helper code, bundle it in `scripts/`.
- Wasted turns: read the run transcripts, not only the outputs, and cut instructions that send the model down unproductive paths.
