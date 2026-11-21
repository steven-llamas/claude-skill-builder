<#
Validate, then zip a skill folder for upload to Claude.ai (Settings > Capabilities > Skills).
PowerShell port of package_skill.py, for machines without Python.
Works in Windows PowerShell 5.1 and PowerShell 7 (pwsh).

Usage: powershell -NoProfile -ExecutionPolicy Bypass -File package_skill.ps1 PATH_TO_SKILL_FOLDER [OUTPUT_DIR]
Writes OUTPUT_DIR/skill-name.zip (default OUTPUT_DIR: the skill's parent folder).
The zip holds the skill folder at its root, with forward-slash entry names. Excludes evals/,
__pycache__/, node_modules/, *.pyc, and dotfiles, matching package_skill.py.
#>
param(
    [Parameter(Position = 0)][string]$Skill,
    [Parameter(Position = 1)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

function Resolve-UserPath([string]$p) {
    if ($p.StartsWith('~')) { $p = $HOME + $p.Substring(1) }
    return [System.IO.Path]::GetFullPath($p).TrimEnd('\', '/')
}

if (-not $Skill) {
    Write-Output 'Usage: powershell -NoProfile -ExecutionPolicy Bypass -File package_skill.ps1 PATH_TO_SKILL_FOLDER [OUTPUT_DIR]'
    exit 2
}
$skillPath = Resolve-UserPath $Skill
if ($OutDir) { $out = Resolve-UserPath $OutDir } else { $out = [System.IO.Path]::GetDirectoryName($skillPath) }

& (Join-Path $PSScriptRoot 'validate_skill.ps1') $skillPath
if ($LASTEXITCODE -ne 0) {
    Write-Output 'Packaging stopped: fix the validation errors above first.'
    exit 1
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$name = [System.IO.Path]::GetFileName($skillPath)
[void][System.IO.Directory]::CreateDirectory($out)
$zipPath = Join-Path $out ($name + '.zip')
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

$script:Count = 0
function Add-Folder($zip, [string]$dir, [bool]$isRoot) {
    foreach ($f in [System.IO.Directory]::GetFiles($dir)) {
        $fn = [System.IO.Path]::GetFileName($f)
        if ($fn.StartsWith('.') -or $fn.EndsWith('.pyc')) { continue }
        if ([System.IO.Path]::GetFullPath($f) -eq $zipPath) { continue }
        $arc = $name + '/' + $f.Substring($skillPath.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f, $arc, [System.IO.Compression.CompressionLevel]::Optimal)
        $script:Count++
    }
    foreach ($d in [System.IO.Directory]::GetDirectories($dir)) {
        $dn = [System.IO.Path]::GetFileName($d)
        if ($dn.StartsWith('.') -or $dn -eq '__pycache__' -or $dn -eq 'node_modules') { continue }
        if ($isRoot -and $dn -eq 'evals') { continue }  # test data stays out of the shipped skill
        Add-Folder $zip $d $false
    }
}

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try { Add-Folder $zip $skillPath $true } finally { $zip.Dispose() }
Write-Output "Packaged $($script:Count) files into $zipPath"
exit 0
