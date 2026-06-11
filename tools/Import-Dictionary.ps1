param(
  [Parameter(Mandatory = $true)]
  [string]$Url,

  [string]$OutFile = "data/external/imported.tsv"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$target = Join-Path $root $OutFile
$targetDir = Split-Path -Parent $target

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
Invoke-WebRequest -Uri $Url -OutFile $target

Write-Host "Downloaded dictionary TSV to $target"
Write-Host "Run: pwsh ./tools/Build-Dictionaries.ps1"
