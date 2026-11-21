<#
Scaffold a new skill folder from a category template.
PowerShell port of scaffold_skill.py, for machines without Python.
Works in Windows PowerShell 5.1 and PowerShell 7 (pwsh).

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File scaffold_skill.ps1 -Name my-skill -Category workflow `
      -Out ~/.claude/skills -Description "Does X. Use when user says ..." `
      [-With scripts,references,assets] [-Cases case-one,case-two] [-Force]

Categories: document, workflow, mcp.
-Cases writes test case folders under evals/ in the layout skill-creator and
`claude plugin eval` read, plus evals/trigger-queries.json, all with [TODO ...]
markers that the validator reports until they are filled.
Keep the templates in step with scaffold_skill.py.
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][ValidateSet('document', 'workflow', 'mcp')][string]$Category,
    [string]$Out = '~/.claude/skills',
    [string]$Description = '[TODO: What it does. Use when user says "phrase".]',
    [string]$With = '',
    [string]$Cases = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$MAX_NAME = 64
$RESERVED_CASES = @('false', 'files', 'mocks', 'node_modules', 'null', 'results', 'true')

$Bodies = @{}
$Bodies['document'] = @'
# {title}

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
'@
$Bodies['workflow'] = @'
# {title}

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
'@
$Bodies['mcp'] = @'
# {title}

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
'@

$PromptMd = @'
---
tags: [skill-builder]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

[TODO: the prompt exactly as a real user would type it, with realistic detail]
'@
$CaseYaml = @'
schema_version: "1.1"
name: {case}
expected_outcome: |
  [TODO: what a good result looks like]
'@
$PlaceholderGrader = @'
---
type: llm
focus: trace
weight: 1
---

The result matches this description: [TODO: the expected outcome]
'@
$TriggerQueries = @'
[
  {"query": "[TODO: realistic prompt that should load the skill]", "should_trigger": true},
  {"query": "[TODO: near-miss prompt that should not load it]", "should_trigger": false}
]
'@

function Stop-WithError([string]$msg) { [Console]::Error.WriteLine("ERROR: $msg"); exit 1 }

# UTF-8 without BOM and LF line endings, matching the Python scaffolder.
function Write-NewFile([string]$path, [string]$content, [bool]$overwrite) {
    if ((Test-Path -LiteralPath $path) -and -not $overwrite) { Write-Output "Kept existing $path"; return }
    $text = $content.Replace("`r`n", "`n")
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

function New-EvalScaffold([string]$root, [string[]]$caseNames) {
    $evals = Join-Path $root 'evals'
    foreach ($c in $caseNames) {
        $d = Join-Path $evals $c
        [void][System.IO.Directory]::CreateDirectory((Join-Path $d 'graders'))
        Write-NewFile (Join-Path $d 'prompt.md') $PromptMd $false
        Write-NewFile (Join-Path $d 'case.yaml') $CaseYaml.Replace('{case}', $c) $false
        Write-NewFile (Join-Path $d 'graders/01-expected-output.md') $PlaceholderGrader $false
    }
    [void][System.IO.Directory]::CreateDirectory($evals)
    Write-NewFile (Join-Path $evals 'trigger-queries.json') $TriggerQueries $false
    Write-Output "Created $($caseNames.Count) test case folder(s) and trigger-queries.json under $evals"
}

if ($Name -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or $Name.Length -gt $MAX_NAME) {
    Stop-WithError "name must be kebab-case (lowercase, digits, hyphens), at most $MAX_NAME characters."
}
if ($Name -match 'claude|anthropic') { Stop-WithError "name must not contain reserved words 'claude' or 'anthropic'." }
if ($Description.Contains('<') -or $Description.Contains('>')) { Stop-WithError 'description must not contain angle brackets.' }

$extras = @($With.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$bad = @($extras | Where-Object { @('scripts', 'references', 'assets') -notcontains $_ })
if ($bad.Count -gt 0) { Stop-WithError "unknown -With values: $($bad -join ', ')" }

$caseList = @($Cases.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$badCases = @($caseList | Where-Object { $_ -cnotmatch '^[a-z][a-z0-9-]*$' -or $RESERVED_CASES -contains $_ })
if ($badCases.Count -gt 0) {
    Stop-WithError ("bad case name(s) $($badCases -join ', '): lowercase letters, digits, hyphens, starting with a letter; " +
        "not one of $($RESERVED_CASES -join ', ').")
}

$outDir = $Out
if ($outDir.StartsWith('~')) { $outDir = $HOME + $outDir.Substring(1) }
$root = [System.IO.Path]::GetFullPath((Join-Path $outDir $Name))
$skillMd = Join-Path $root 'SKILL.md'
if ((Test-Path -LiteralPath $skillMd) -and -not $Force) {
    if ($caseList.Count -gt 0) { New-EvalScaffold $root $caseList; exit 0 }  # add tests to an existing skill
    Stop-WithError "$skillMd exists. Use -Force to overwrite."
}
[void][System.IO.Directory]::CreateDirectory($root)
foreach ($e in $extras) { [void][System.IO.Directory]::CreateDirectory((Join-Path $root $e)) }

$desc = $Description.Replace('"', "'")
$title = (($Name -split '-') | ForEach-Object { if ($_) { $_.Substring(0, 1).ToUpper() + $_.Substring(1) } }) -join ' '
$content = "---`nname: $Name`ndescription: `"$desc`"`nmetadata:`n  version: 0.1.0`n---`n`n" + $Bodies[$Category].Replace('{title}', $title)
Write-NewFile $skillMd $content $true
Write-Output "Created $skillMd"
if ($caseList.Count -gt 0) { New-EvalScaffold $root $caseList }
Write-Output 'Next: fill every [TODO ...] marker, then run validate_skill.ps1 (or validate_skill.py) on the folder.'
