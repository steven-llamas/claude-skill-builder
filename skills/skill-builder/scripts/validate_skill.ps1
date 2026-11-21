<#
Validate a skill folder against the Claude skill-building guide.
PowerShell port of validate_skill.py, for machines without Python.
Works in Windows PowerShell 5.1 and PowerShell 7 (pwsh).

Usage: powershell -NoProfile -ExecutionPolicy Bypass -File validate_skill.ps1 PATH_TO_SKILL_FOLDER
Exit code 0 = PASS (warnings allowed), 1 = FAIL (one or more errors), 2 = usage.
Keep the checks in step with validate_skill.py.
#>
param([Parameter(Position = 0)][string]$Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$MAX_NAME = 64
$MAX_DESC = 1024
$MAX_COMPAT = 500
$MAX_BODY_LINES = 500
$MAX_BODY_WORDS = 5000
$TOC_LINES = 100
$MIN_TRIGGER = 8
$ALLOWED_KEYS = @('name', 'description', 'license', 'allowed-tools', 'metadata', 'compatibility')
$CLAUDE_CODE_KEYS = @('when_to_use', 'argument-hint', 'arguments', 'disable-model-invocation', 'user-invocable',
    'model', 'effort', 'context', 'agent', 'hooks', 'paths', 'shell')
$PROMPT_KEYS = @('tags', 'max_turns', 'timeout_seconds', 'allowed_tools')
$EVAL_SKIP_DIRS = @('results', 'mocks', 'node_modules', 'files')
$NAME_RE = '^[a-z0-9]+(-[a-z0-9]+)*$'
$CASE_RE = '^[a-z][a-z0-9-]*$'
$TRIGGER_RE = '\b(use (it |this |this skill )?(when|whenever|for|if)|trigger|whenever|when (the )?users?\b|if the user)'
$FIRST_PERSON_RE = '\b(I can|I will|I help|you can use|you can|helps you|you should)\b'
$BLOCK_SCALAR = '^[>|][+-]?$'
$CODE_RE = '(?s)```.*?```|`[^`\n]*`'
$IC = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$ML = [System.Text.RegularExpressions.RegexOptions]::Multiline

$script:Errors = New-Object System.Collections.Generic.List[string]
$script:Warns = New-Object System.Collections.Generic.List[string]
function Add-Err([string]$m) { $script:Errors.Add($m) }
function Add-Warn([string]$m) { $script:Warns.Add($m) }

function Read-Utf8([string]$p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }

function Sort-Ordinal($items) {
    $a = [string[]]@($items)
    [Array]::Sort($a, [System.StringComparer]::Ordinal)
    return , $a
}

function ConvertFrom-QuotedValue([string]$v) {
    if ($v.Length -ge 2 -and $v[0] -eq '"' -and $v[$v.Length - 1] -eq '"') {
        return $v.Substring(1, $v.Length - 2).Replace('\"', '"').Replace('\\', '\')
    }
    if ($v.Length -ge 2 -and $v[0] -eq "'" -and $v[$v.Length - 1] -eq "'") {
        return $v.Substring(1, $v.Length - 2).Replace("''", "'")
    }
    return $v
}

# Returns @{ Fm = ordered map or $null; Body = string }. Nested mappings are stored as @{ _raw = text }.
function ConvertFrom-Frontmatter([string]$text) {
    $lines = $text.Replace("`r`n", "`n").Split("`n")
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') { return @{ Fm = $null; Body = $text } }
    $end = -1
    for ($k = 1; $k -lt $lines.Count; $k++) { if ($lines[$k].Trim() -eq '---') { $end = $k; break } }
    if ($end -lt 0) { return @{ Fm = $null; Body = $text } }
    $fm = [ordered]@{}
    $bl = @()
    if ($end -gt 1) { $bl = $lines[1..($end - 1)] }
    $i = 0
    while ($i -lt $bl.Count) {
        $m = [regex]::Match($bl[$i], '^([A-Za-z0-9_-]+):\s*(.*)$')
        if (-not $m.Success) { $i++; continue }
        $key = $m.Groups[1].Value
        $val = $m.Groups[2].Value.Trim()
        $block = New-Object System.Collections.Generic.List[string]
        $i++
        while ($i -lt $bl.Count -and ($bl[$i].StartsWith(' ') -or $bl[$i].StartsWith("`t") -or -not $bl[$i].Trim())) {
            $block.Add($bl[$i].Trim()); $i++
        }
        while ($block.Count -gt 0 -and -not $block[$block.Count - 1]) { $block.RemoveAt($block.Count - 1) }
        if ($val -match $BLOCK_SCALAR) {
            $sep = ' '; if ($val[0] -eq '|') { $sep = "`n" }
            $fm[$key] = ($block -join $sep).Trim()
        } elseif ($val) {
            $parts = @($val) + @($block | Where-Object { $_ })
            $fm[$key] = ConvertFrom-QuotedValue (($parts -join ' ').Trim())
        } else {
            $fm[$key] = @{ _raw = ($block -join "`n") }
        }
    }
    $rest = ''
    if ($end + 1 -lt $lines.Count) { $rest = $lines[($end + 1)..($lines.Count - 1)] -join "`n" }
    return @{ Fm = $fm; Body = $rest }
}

function Get-RelPath([string]$root, [string]$full) {
    $r = $root.TrimEnd('\', '/')
    return $full.Substring($r.Length + 1).Replace('\', '/')
}

# Recursive file listing that skips the named folders (and dot-folders when asked).
function Get-WalkFiles([string]$dir, [string[]]$skipDirs, [bool]$skipDot) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($f in [System.IO.Directory]::GetFiles($dir)) { $out.Add($f) }
    foreach ($d in [System.IO.Directory]::GetDirectories($dir)) {
        $n = [System.IO.Path]::GetFileName($d)
        if ($skipDirs -contains $n) { continue }
        if ($skipDot -and $n.StartsWith('.')) { continue }
        foreach ($f in (Get-WalkFiles $d $skipDirs $skipDot)) { $out.Add($f) }
    }
    return , $out
}

function Test-Evals([string]$evals) {
    if (-not [System.IO.Directory]::Exists($evals)) {
        Add-Warn 'No evals/ folder. Add test cases (scaffold_skill.py --cases) so the skill can be tested.'
        return
    }
    $cases = New-Object System.Collections.Generic.List[string]
    $names = Sort-Ordinal @([System.IO.Directory]::GetDirectories($evals) | ForEach-Object { [System.IO.Path]::GetFileName($_) })
    foreach ($e in $names) {
        if (-not $e) { continue }
        $d = Join-Path $evals $e
        if ($EVAL_SKIP_DIRS -contains $e -or $e.StartsWith('.')) { continue }
        $pm = Join-Path $d 'prompt.md'
        $cy = Join-Path $d 'case.yaml'
        if (-not ([System.IO.File]::Exists($pm) -or [System.IO.File]::Exists($cy))) { continue }
        $cases.Add($e)
        $tag = "evals/$e"
        if ($e -cnotmatch $CASE_RE -or @('true', 'false', 'null') -contains $e) {
            Add-Err "${tag}: case name must be lowercase letters, digits, hyphens, starting with a letter."
        }
        foreach ($fn in @('prompt.md', 'case.yaml')) {
            if (-not [System.IO.File]::Exists((Join-Path $d $fn))) { Add-Err "${tag}: $fn missing." }
        }
        if ([System.IO.File]::Exists($pm)) {
            $ptext = Read-Utf8 $pm
            $p = ConvertFrom-Frontmatter $ptext
            if ($ptext.TrimStart().StartsWith('---') -and $null -eq $p.Fm) {
                Add-Err "$tag/prompt.md: settings block is not closed with ---."
            }
            if ($null -ne $p.Fm) {
                $extra = Sort-Ordinal @($p.Fm.Keys | Where-Object { $PROMPT_KEYS -notcontains $_ })
                if ($extra.Count -gt 0) {
                    Add-Err "$tag/prompt.md: unknown setting(s) $($extra -join ', ') make the case fail to load."
                }
                $ptxt = $p.Body
            } else { $ptxt = $ptext }
            if (-not $ptxt.Trim()) { Add-Err "$tag/prompt.md: no prompt text after the settings block." }
        }
        if ([System.IO.File]::Exists($cy)) {
            $ytext = Read-Utf8 $cy
            if (-not [regex]::IsMatch($ytext, '^schema_version:\s*["'']1\.1["'']\s*$', $ML)) {
                Add-Err "$tag/case.yaml: needs schema_version: `"1.1`" (quoted, or it reads as a number)."
            }
            $m = [regex]::Match($ytext, '^name:\s*["'']?([^"''\n]+?)["'']?\s*$', $ML)
            if (-not $m.Success -or $m.Groups[1].Value -cne $e) {
                Add-Err "$tag/case.yaml: name must equal the folder name '$e'."
            }
        }
        $gdir = Join-Path $d 'graders'
        $graders = @()
        if ([System.IO.Directory]::Exists($gdir)) {
            $graders = Sort-Ordinal @([System.IO.Directory]::GetFiles($gdir, '*.md') | ForEach-Object { [System.IO.Path]::GetFileName($_) })
            $graders = @($graders | Where-Object { $_ })
        }
        if ($graders.Count -eq 0) {
            Add-Err "${tag}: no graders/*.md; a case with no grader fails to load (keep the placeholder until real ones exist)."
        }
        foreach ($g in $graders) {
            $gp = ConvertFrom-Frontmatter (Read-Utf8 (Join-Path $gdir $g))
            if ($null -eq $gp.Fm -or -not $gp.Fm.Contains('type')) {
                Add-Err "$tag/graders/${g}: needs a settings block with type (the CLI ignores it otherwise)."
            }
        }
        foreach ($f in (Get-WalkFiles $d @() $false)) {
            if ($f.EndsWith('.md') -or $f.EndsWith('.yaml')) {
                if ((Read-Utf8 $f).Contains('[TODO')) {
                    Add-Err "${tag}: unfilled [TODO ...] marker in $(Get-RelPath $d $f)."
                }
            }
        }
    }
    if ($cases.Count -eq 0) {
        if ([System.IO.File]::Exists((Join-Path $evals 'evals.json'))) {
            Add-Warn 'Only evals/evals.json (older format). Add case folders; skill-creator and claude plugin eval run those.'
        } else {
            Add-Warn 'evals/ has no test case folders (each needs prompt.md, case.yaml, graders/).'
        }
    } elseif ($cases.Count -lt 2) {
        Add-Warn "Only $($cases.Count) test case; 2 to 3 realistic cases give a more useful signal."
    }

    $tq = Join-Path $evals 'trigger-queries.json'
    if (-not [System.IO.File]::Exists($tq)) {
        Add-Warn 'No evals/trigger-queries.json; description tuning needs should and should-not trigger queries.'
        return
    }
    $raw = Read-Utf8 $tq
    try { $parsed = ConvertFrom-Json -InputObject $raw } catch {
        Add-Err ("evals/trigger-queries.json is not valid JSON: " + ($_.Exception.Message -replace '\s*[\r\n]+\s*', ' ').Trim())
        return
    }
    $shapeMsg = 'evals/trigger-queries.json must be a list of {"query": "...", "should_trigger": true|false}.'
    if (-not $raw.Trim().StartsWith('[')) { Add-Err $shapeMsg; return }
    $items = @()
    foreach ($x in $parsed) { $items += , $x }
    foreach ($it in $items) {
        $props = @()
        if ($null -ne $it -and $it -is [System.Management.Automation.PSCustomObject]) { $props = @($it.PSObject.Properties.Name) }
        if ($props -notcontains 'query' -or $props -notcontains 'should_trigger' -or
            -not ($it.query -is [string]) -or -not ($it.should_trigger -is [bool])) {
            Add-Err $shapeMsg; return
        }
    }
    if (@($items | Where-Object { $_.query.Contains('[TODO') }).Count -gt 0) {
        Add-Err 'evals/trigger-queries.json: unfilled [TODO ...] queries.'
    }
    $pos = @($items | Where-Object { $_.should_trigger }).Count
    $neg = $items.Count - $pos
    if ($pos -lt $MIN_TRIGGER -or $neg -lt $MIN_TRIGGER) {
        Add-Warn "trigger-queries.json has $pos should-trigger and $neg should-not; aim for $MIN_TRIGGER to 10 of each."
    }
}

function Write-Report {
    foreach ($w in $script:Warns) { Write-Output ('WARN:  ' + $w) }
    foreach ($e in $script:Errors) { Write-Output ('ERROR: ' + $e) }
    $res = 'PASS'; if ($script:Errors.Count -gt 0) { $res = 'FAIL' }
    Write-Output "RESULT: $res ($($script:Errors.Count) errors, $($script:Warns.Count) warnings)"
}

function Invoke-Validate([string]$p) {
    if ($p.StartsWith('~')) { $p = $HOME + $p.Substring(1) }
    $p = [System.IO.Path]::GetFullPath($p).TrimEnd('\', '/')
    if (-not [System.IO.Directory]::Exists($p)) { Write-Output "ERROR: not a directory: $p"; $script:Errors.Add('not a directory'); return }
    $folder = [System.IO.Path]::GetFileName($p)
    $entries = @([System.IO.Directory]::GetFileSystemEntries($p) | ForEach-Object { [System.IO.Path]::GetFileName($_) })

    if ($entries -cnotcontains 'SKILL.md') {
        $near = @($entries | Where-Object { $_.ToLower() -eq 'skill.md' })
        if ($near.Count -gt 0) { Add-Err "SKILL.md missing; found '$($near[0])'. Rename to exactly SKILL.md." }
        else { Add-Err 'SKILL.md missing in skill folder.' }
        Write-Report; return
    }
    if (@($entries | Where-Object { $_.ToLower() -eq 'readme.md' }).Count -gt 0) {
        Add-Err 'README.md present in skill folder. Move content to SKILL.md or references/.'
    }
    $nested = New-Object System.Collections.Generic.List[string]
    foreach ($f in (Get-WalkFiles $p @('__pycache__', 'node_modules', 'evals') $true)) {
        if ([System.IO.Path]::GetFileName($f) -ceq 'SKILL.md' -and [System.IO.Path]::GetDirectoryName($f) -ne $p) {
            $nested.Add((Get-RelPath $p $f))
        }
    }
    if ($nested.Count -gt 0) {
        Add-Err "Nested SKILL.md file(s): $($nested -join ', '). Uploads reject more than one; rename supporting docs."
    }
    if ($folder -cnotmatch $NAME_RE) {
        Add-Err "Folder name '$folder' must be kebab-case (lowercase, digits, single hyphens)."
    }

    $parsed = ConvertFrom-Frontmatter (Read-Utf8 (Join-Path $p 'SKILL.md'))
    $fm = $parsed.Fm
    $body = $parsed.Body
    if ($null -eq $fm) {
        Add-Err 'Frontmatter missing or unclosed: file must start with --- and close with ---.'
        Write-Report; return
    }
    $keys = @($fm.Keys)
    $ccOnly = Sort-Ordinal @($keys | Where-Object { $CLAUDE_CODE_KEYS -contains $_ })
    if ($ccOnly.Count -gt 0) {
        Add-Warn "Frontmatter key(s) $($ccOnly -join ', ') work in Claude Code but a Claude.ai upload rejects them."
    }
    $unexpected = Sort-Ordinal @($keys | Where-Object { $ALLOWED_KEYS -notcontains $_ -and $CLAUDE_CODE_KEYS -notcontains $_ })
    if ($unexpected.Count -gt 0) {
        Add-Err ("Unexpected frontmatter key(s): $($unexpected -join ', '). Allowed: $((Sort-Ordinal $ALLOWED_KEYS) -join ', '). " +
            'Put custom fields under metadata.')
    }
    foreach ($k in $keys) {
        $v = $fm[$k]
        if ($v -is [hashtable]) { $s = [string]$v['_raw'] } else { $s = [string]$v }
        if ($s.Contains('<') -or $s.Contains('>')) {
            Add-Err "Frontmatter field '$k' contains angle brackets (< or >), which are forbidden."
        }
    }

    $name = ''
    if ($fm.Contains('name')) { $name = $fm['name'] }
    if (-not ($name -is [string]) -or -not $name) {
        Add-Err 'Frontmatter: name is required (a string).'
    } else {
        if ($name -cnotmatch $NAME_RE) {
            Add-Err "name '$name' must be kebab-case: lowercase letters, digits, single hyphens; no spaces or capitals."
        }
        if ($name.Length -gt $MAX_NAME) { Add-Err "name is $($name.Length) characters; max $MAX_NAME." }
        if ($name -match 'claude|anthropic') { Add-Err "name must not contain reserved words 'claude' or 'anthropic'." }
        if ($name -cne $folder) { Add-Err "name '$name' should match folder name '$folder'." }
    }

    $desc = ''
    if ($fm.Contains('description')) { $desc = $fm['description'] }
    if (-not ($desc -is [string]) -or -not $desc) {
        Add-Err 'Frontmatter: description is required and non-empty.'
    } else {
        if ($desc.Length -gt $MAX_DESC) { Add-Err "description is $($desc.Length) characters; max $MAX_DESC." }
        if (-not [regex]::IsMatch($desc, $TRIGGER_RE, $IC)) {
            Add-Err "description has no trigger condition. Add 'Use when the user ...' with concrete phrases or contexts."
        }
        if ($desc.Length -lt 100) {
            Add-Warn 'description is short; Claude tends to undertrigger, so add contexts, phrases, and file types.'
        }
        if ([regex]::IsMatch($desc, $FIRST_PERSON_RE, $IC)) {
            Add-Warn "description should be third person (avoid 'I can', 'you can', 'helps you')."
        }
        if (-not ($desc.Contains('"') -or $desc.Contains("'") -or $desc.Contains([string][char]0x201C))) {
            Add-Warn 'description has no quoted user phrases; real phrases users type improve triggering.'
        }
    }

    if ($fm.Contains('compatibility')) {
        $compat = $fm['compatibility']
        if ($compat -is [string] -and $compat.Length -gt $MAX_COMPAT) {
            Add-Err "compatibility must be at most $MAX_COMPAT characters (is $($compat.Length))."
        }
    }

    $noCode = [regex]::Replace($body, $CODE_RE, '')
    $bodyLines = @($body.Trim() -split "`n")
    $words = @($body -split '\s+' | Where-Object { $_ }).Count
    if ($bodyLines.Count -gt $MAX_BODY_LINES) {
        Add-Warn "SKILL.md body is $($bodyLines.Count) lines; aim for under $MAX_BODY_LINES. Move detail to linked files."
    }
    if ($words -gt $MAX_BODY_WORDS) {
        Add-Warn "SKILL.md body is $words words; keep under $MAX_BODY_WORDS. Move detail to linked files."
    }
    if ([regex]::IsMatch($noCode, '\[TODO', $IC) -or ($desc -is [string] -and $desc.Contains('[TODO'))) {
        Add-Err 'Unfilled [TODO ...] markers remain.'
    }
    if (-not [regex]::IsMatch($body, '^#{1,4}\s+.*example', $IC -bor $ML)) {
        Add-Warn 'No Examples section; the guide recommends at least 2 (user says, actions, result).'
    }
    if (-not [regex]::IsMatch($body, '^#{1,4}\s+.*(troubleshoot|common issues|error|if something fails|failure)', $IC -bor $ML)) {
        Add-Warn 'No Troubleshooting or error-handling section.'
    }
    if ([regex]::IsMatch($noCode, '</?[A-Za-z][A-Za-z0-9_-]*(\s[^>\n]*)?>')) {
        Add-Warn 'Body contains XML-like tags outside code spans; prefer Markdown.'
    }
    if ([regex]::IsMatch($noCode, '\b[\w.-]+\\[\w.-]+\\?')) {
        Add-Warn 'Possible Windows backslash path; use forward slashes.'
    }

    # bundled files: docs must be reachable from SKILL.md (no hidden chains)
    $unrefDocs = New-Object System.Collections.Generic.List[string]
    $longDocs = New-Object System.Collections.Generic.List[string]
    $unrefDirs = New-Object System.Collections.Generic.List[string]
    foreach ($e in (Sort-Ordinal $entries)) {
        if (-not $e -or $e.StartsWith('.') -or $e -eq '__pycache__' -or $e -eq 'evals') { continue }
        $full = Join-Path $p $e
        if (-not [System.IO.Directory]::Exists($full)) { continue }
        if (-not $body.Contains($e)) { $unrefDirs.Add($e + '/') }
        foreach ($f in (Get-WalkFiles $full @('__pycache__', 'node_modules') $false)) {
            $fn = [System.IO.Path]::GetFileName($f)
            $low = $fn.ToLower()
            if (($low.EndsWith('.md') -or $low.EndsWith('.txt')) -and $fn -ne 'LICENSE.txt') {
                $rel = Get-RelPath $p $f
                if (-not $body.Contains($rel) -and -not $body.Contains($fn)) { $unrefDocs.Add($rel) }
                $content = Read-Utf8 $f
                if ($fn.EndsWith('.md') -and @($content -split "`n").Count -gt $TOC_LINES -and
                    -not [regex]::IsMatch($content, '^#+\s*(table of )?contents', $IC -bor $ML)) {
                    $longDocs.Add($rel)
                }
            }
        }
    }
    if ($unrefDirs.Count -gt 0) {
        Add-Warn "Folder(s) never mentioned in SKILL.md: $($unrefDirs -join ', '). Claude will not know they exist."
    }
    if ($unrefDocs.Count -gt 0) {
        $shown = @($unrefDocs | Select-Object -First 8)
        $more = ''; if ($unrefDocs.Count -gt 8) { $more = ' ...' }
        Add-Warn "Doc file(s) not linked directly from SKILL.md (keep references one level deep): $($shown -join ', ')$more"
    }
    if ($longDocs.Count -gt 0) {
        Add-Warn "Doc file(s) over $TOC_LINES lines without a Contents section: $($longDocs -join ', ')"
    }
    # Check paths in prose and inline code spans, but not fenced blocks (example commands).
    $noFences = [regex]::Replace($body, '(?s)```.*?```', '')
    $refs = @([regex]::Matches($noFences, '\b((?:references|scripts|assets)/[\w./-]*\w)') | ForEach-Object { $_.Groups[1].Value })
    foreach ($ref in (Sort-Ordinal @($refs | Select-Object -Unique))) {
        if (-not $ref) { continue }
        if (-not $ref.Contains('*') -and -not (Test-Path -LiteralPath (Join-Path $p $ref))) {
            Add-Err "SKILL.md links $ref but it does not exist. Create it or remove the reference."
        }
    }

    Test-Evals (Join-Path $p 'evals')
    Write-Report; return
}

if (-not $Path) {
    Write-Output 'Usage: powershell -NoProfile -ExecutionPolicy Bypass -File validate_skill.ps1 PATH_TO_SKILL_FOLDER'
    exit 2
}
Invoke-Validate $Path
if ($script:Errors.Count -gt 0) { exit 1 }
exit 0
