# Category templates and patterns

## Contents
- Choosing a category
- Category 1: Document and asset creation
- Category 2: Workflow automation
- Category 3: MCP enhancement
- Pattern snippets

## Choosing a category

| If the skill mainly... | Category | Typical pattern |
|---|---|---|
| Produces consistent documents, designs, code, decks | document | Domain-specific intelligence + templates + quality checklist |
| Runs an ordered multi-step process | workflow | Sequential orchestration, iterative refinement |
| Guides use of an MCP server's tools | mcp | Sequential, multi-MCP, context-aware selection |

Framing: problem-first (user states an outcome, skill picks the calls) or tool-first (user has a connector, skill supplies best practice). Most skills lean one way; say which in the body intro.

## Category 1: Document and asset creation

Techniques: embedded style guide, output template in `assets/`, quality checklist before finalizing, no external tools required.

Body skeleton:
1. Critical rules (voice, forbidden content, required sections)
2. Step 1 gather inputs; Step 2 draft from `assets/template` ; Step 3 run quality checklist; Step 4 finalize
3. Quality checklist (each item testable)
4. Examples; troubleshooting

## Category 2: Workflow automation

Techniques: explicit step order, validation gates between steps, rollback or recovery instructions, refinement loop with a stop condition.

Body skeleton:
1. Critical rules
2. Step N: action, expected output, validation, on-failure behavior
3. Refinement loop: criteria, max iterations, when to stop
4. Examples; troubleshooting

## Category 3: MCP enhancement

Techniques: coordinate calls in sequence, pass data between steps, embed domain expertise, handle common MCP errors.

Body skeleton:
1. Prerequisites (server connected, auth, scopes)
2. Step N: `ServerName:tool_name`, parameters, data carried to the next step
3. Common issues: connection refused, expired auth, wrong tool name, permission scopes
4. Examples; troubleshooting (test the MCP independently first to isolate the fault)

## Pattern snippets

**Sequential orchestration**: Step 1 call, Step 2 call using output of Step 1, wait for verification, rollback on failure.

**Multi-MCP coordination**: Phase per service, validate before the next phase, pass identifiers between phases, centralized error handling.

**Iterative refinement**: Draft, run `scripts/check_*.py`, list issues, fix, re-validate, stop when criteria met or after N rounds, then finalize.

**Context-aware selection**: Decision tree on file type, size, or audience; fallback option; tell the user why the choice was made.

**Domain-specific intelligence**: Rules check before action, document the decision, audit trail, flag exceptions for human review.
