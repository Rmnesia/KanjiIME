param(
  [string]$DataDir = "data",
  [string]$RimeDir = "rime"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$dataPath = Join-Path $root $DataDir
$rimePath = Join-Path $root $RimeDir
$commonWordsFile = Join-Path $root "data/common/google-10000-english-usa-no-swears.txt"

if (!(Test-Path $dataPath)) {
  throw "Data directory not found: $dataPath"
}

New-Item -ItemType Directory -Force -Path $rimePath | Out-Null

$commonRanks = @{}
if (Test-Path $commonWordsFile) {
  $rank = 0
  Get-Content -LiteralPath $commonWordsFile -Encoding UTF8 | ForEach-Object {
    $word = $_.Trim().ToLowerInvariant()
    if ($word -and !$commonRanks.ContainsKey($word)) {
      $rank++
      $commonRanks[$word] = $rank
    }
  }
}

$modes = @{
  jp = [System.Collections.Generic.List[object]]::new()
  zh = [System.Collections.Generic.List[object]]::new()
  hk = [System.Collections.Generic.List[object]]::new()
}

function Get-CandidateScore([string]$Mode, [string]$English, [string]$Candidate, [int]$Weight, [string]$Comment) {
  $length = [System.Globalization.StringInfo]::ParseCombiningCharacters($Candidate).Count
  $score = $Weight
  $isCommonEnglish = $commonRanks.ContainsKey($English) -and $commonRanks[$English] -le 2000

  if ($isCommonEnglish) {
    $score += [Math]::Max(0, 900 - [int]($commonRanks[$English] / 3))
  }

  if ($Mode -eq "jp") {
    if ($Candidate -notmatch "[\u3400-\u9fff]") { return -1 }
    if ($length -le 1) { $score += 900 }
    elseif ($length -eq 2) { $score += 380 }
    elseif ($length -eq 3) { $score += 220 }
    elseif ($length -eq 4) { $score += 100 }
    else { $score -= [Math]::Min(300, ($length - 4) * 35) }
    if ($Candidate -match "[\u30a0-\u30ff]") { $score -= 240 }
    if ($Candidate -match "[\u3040-\u309f]") { $score -= 60 }
  } else {
    if ($Candidate -match "[a-zA-Z0-9]") { $score -= 700 }
    if ($Candidate -match "[，,。.！？!?；;：:]") { $score -= 450 }
    if ($Candidate -match "[\u3400-\u4dbf]") { $score -= 350 }

    if ($isCommonEnglish) {
      if ($length -eq 2) { $score += 820 }
      elseif ($length -eq 1) { $score += 120 }
      elseif ($length -eq 3) { $score += 360 }
      elseif ($length -eq 4) { $score += 180 }
      else { $score -= [Math]::Min(900, ($length - 4) * 90) }
    } else {
      if ($length -eq 2) { $score += 620 }
      elseif ($length -eq 1) { $score += 300 }
      elseif ($length -eq 3) { $score += 280 }
      elseif ($length -eq 4) { $score += 110 }
      else { $score -= [Math]::Min(700, ($length - 4) * 70) }
    }

    if ($Comment -match "common-override") { $score += 5000 }
    elseif ($Comment -match "curated") { $score += 3600 }
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
    if ((Split-Path -Leaf $file) -eq "seed.tsv") {
      $weight += 3000
    }

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
        Score = Get-CandidateScore $target $english $candidate $weight $comment
        Comment = $comment
      })
    }
  }
}

foreach ($mode in $modes.Keys) {
  $name = "kanji_en_$mode"
  $outFile = Join-Path $rimePath "$name.dict.yaml"

  if ($commonRanks.Count -gt 0) {
    $presentEnglish = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in $modes[$mode]) {
      if ($row.Score -ge 0) { $presentEnglish.Add($row.English) | Out-Null }
    }

    foreach ($entry in $commonRanks.GetEnumerator()) {
      if ($entry.Value -gt 2000) { continue }
      $english = $entry.Key
      if ($english.Length -lt 3 -or $presentEnglish.Contains($english)) { continue }
      $fallback = if ($mode -eq "zh") { [string][char]0x8BCD } elseif ($mode -eq "hk") { [string][char]0x8A5E } else { [string][char]0x8A9E }
      $modes[$mode].Add([pscustomobject]@{
        English = $english
        Candidate = $fallback
        Weight = 1
        Score = 1
        Comment = "common-empty-fallback"
      })
      $presentEnglish.Add($english) | Out-Null
    }
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("---")
  $lines.Add("name: $name")
  $lines.Add('version: "0.1.0"')
  $lines.Add("sort: by_weight")
  $lines.Add("use_preset_vocabulary: false")
  $lines.Add("...")

  $bestRows = @{}
  foreach ($row in $modes[$mode]) {
    if ($row.Score -lt 0) { continue }
    $id = "$($row.English)|$($row.Candidate)"
    if (!$bestRows.ContainsKey($id) -or $row.Score -gt $bestRows[$id].Score) {
      $bestRows[$id] = $row
    }
  }

  $bestRows.Values |
    Sort-Object English, @{ Expression = "Score"; Descending = $true }, Candidate |
    ForEach-Object {
      $lines.Add("$($_.Candidate)`t$($_.English)`t$($_.Score)")
    }

  Set-Content -LiteralPath $outFile -Value $lines -Encoding UTF8
  Write-Host "Wrote $outFile"
}
