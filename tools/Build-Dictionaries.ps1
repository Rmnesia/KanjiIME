param(
  [string]$DataDir = "data",
  [string]$RimeDir = "rime"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$dataPath = Join-Path $root $DataDir
$rimePath = Join-Path $root $RimeDir

if (!(Test-Path $dataPath)) {
  throw "Data directory not found: $dataPath"
}

New-Item -ItemType Directory -Force -Path $rimePath | Out-Null

$modes = @{
  jp = [System.Collections.Generic.List[object]]::new()
  zh = [System.Collections.Generic.List[object]]::new()
  hk = [System.Collections.Generic.List[object]]::new()
}

function Get-CandidateScore([string]$Mode, [string]$Candidate, [int]$Weight) {
  $length = [System.Globalization.StringInfo]::ParseCombiningCharacters($Candidate).Count
  $score = $Weight

  if ($length -le 1) { $score += 600 }
  elseif ($length -eq 2) { $score += 420 }
  elseif ($length -eq 3) { $score += 260 }
  elseif ($length -eq 4) { $score += 120 }
  else { $score -= [Math]::Min(300, ($length - 4) * 35) }

  if ($Mode -eq "jp") {
    if ($Candidate -notmatch "[\u3400-\u9fff]") { return -1 }
    if ($Candidate -match "[\u30a0-\u30ff]") { $score -= 240 }
    if ($Candidate -match "[\u3040-\u309f]") { $score -= 60 }
  }

  return $score
}

Get-ChildItem -Path $dataPath -Recurse -Filter "*.tsv" | Sort-Object FullName | ForEach-Object {
  $file = $_.FullName
  Get-Content -LiteralPath $file -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if (!$line -or $line.StartsWith("#")) { return }

    $parts = $line -split "`t"
    if ($parts.Count -lt 3) {
      throw "Invalid TSV row in $file`: $line"
    }

    $mode = $parts[0].Trim().ToLowerInvariant()
    $english = $parts[1].Trim().ToLowerInvariant()
    $candidate = $parts[2].Trim()
    $weight = if ($parts.Count -ge 4 -and $parts[3].Trim()) { [int]$parts[3].Trim() } else { 50 }
    $comment = if ($parts.Count -ge 5) { $parts[4].Trim() } else { "" }

    if (!$english -or !$candidate) { return }

    $targets = if ($mode -eq "all") { @("jp", "zh", "hk") } else { @($mode) }
    foreach ($target in $targets) {
      if (!$modes.ContainsKey($target)) {
        throw "Unknown mode '$mode' in $file. Use jp, zh, hk, or all."
      }
      $modes[$target].Add([pscustomobject]@{
        English = $english
        Candidate = $candidate
        Weight = $weight
        Score = Get-CandidateScore $target $candidate $weight
        Comment = $comment
      })
    }
  }
}

foreach ($mode in $modes.Keys) {
  $name = "kanji_en_$mode"
  $outFile = Join-Path $rimePath "$name.dict.yaml"

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("---")
  $lines.Add("name: $name")
  $lines.Add('version: "0.1.0"')
  $lines.Add("sort: by_weight")
  $lines.Add("use_preset_vocabulary: false")
  $lines.Add("...")

  $modes[$mode] |
    Where-Object { $_.Score -ge 0 } |
    Sort-Object English, @{ Expression = "Score"; Descending = $true }, Candidate -Unique |
    ForEach-Object {
      $lines.Add("$($_.Candidate)`t$($_.English)`t$($_.Score)")
    }

  Set-Content -LiteralPath $outFile -Value $lines -Encoding UTF8
  Write-Host "Wrote $outFile"
}
