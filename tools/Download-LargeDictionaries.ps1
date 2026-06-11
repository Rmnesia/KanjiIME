param(
  [string]$DataDir = "data/generated",
  [string]$JpUrl = "ftp://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz",
  [string]$CedictUrl = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz",
  [int]$MaxRowsPerMode = 250000,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$outDir = Join-Path $root $DataDir
$cacheDir = Join-Path $root "build/dictionaries"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

function Download-File([string]$Url, [string]$OutFile) {
  if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 0 -and !$Force) {
    Write-Host "Using cached $OutFile"
    return
  }

  Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    & $curl.Source -L -k --retry 3 --connect-timeout 30 -o $OutFile $Url
    if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 0) { return }
  }

  Invoke-WebRequest -Uri $Url -OutFile $OutFile
  if (!(Test-Path $OutFile) -or (Get-Item $OutFile).Length -eq 0) {
    throw "Failed to download $Url"
  }
}

function Expand-Gzip([string]$Source, [string]$Destination) {
  if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0 -and !$Force) {
    Write-Host "Using cached $Destination"
    return
  }

  $input = [System.IO.File]::OpenRead($Source)
  try {
    $gzip = [System.IO.Compression.GzipStream]::new($input, [System.IO.Compression.CompressionMode]::Decompress)
    try {
      $output = [System.IO.File]::Create($Destination)
      try { $gzip.CopyTo($output) } finally { $output.Dispose() }
    } finally {
      $gzip.Dispose()
    }
  } finally {
    $input.Dispose()
  }
}

function Get-EnglishKeys([string]$Gloss) {
  $text = $Gloss.ToLowerInvariant()
  $text = $text -replace "\(.*?\)", " "
  $text = $text -replace "\[.*?\]", " "
  $text = $text -replace "\{.*?\}", " "
  $text = $text -replace "one's", "ones"
  $text = $text -replace "[^a-z0-9 '\-]", " "
  $text = $text -replace "\s+", " "
  $text = $text.Trim()
  if ($text -match "\d") { return @() }

  $skip = @{
    "the" = 1; "and" = 1; "for" = 1; "with" = 1; "from" = 1; "into" = 1; "onto" = 1
    "that" = 1; "this" = 1; "one" = 1; "ones" = 1; "someone" = 1; "something" = 1
    "being" = 1; "used" = 1; "also" = 1; "variant" = 1; "etc" = 1; "see" = 1
  }

  $keys = [System.Collections.Generic.List[string]]::new()
  foreach ($word in ($text -split " ")) {
    $key = $word.Trim(" '-")
    if ($key.Length -lt 3 -or $skip.ContainsKey($key) -or $key -match "\d") { continue }
    $keys.Add($key)
  }

  if ($text.Length -ge 3 -and $text.Length -le 32 -and $text.Split(" ").Count -le 4 -and $text -notmatch "\d") {
    $phrase = ($text -replace " ", "-").Trim("-")
    if ($phrase -and !$skip.ContainsKey($phrase)) { $keys.Add($phrase) }
  }

  return $keys | Select-Object -Unique
}

function Add-Row($Writer, $Seen, [string]$Mode, [string]$English, [string]$Candidate, [int]$Weight, [string]$Comment) {
  if (!$English -or !$Candidate -or $English.Length -gt 40 -or $Candidate.Length -gt 24) { return $false }
  if ($Candidate -notmatch "[\u3040-\u30ff\u3400-\u9fff]") { return $false }
  if ($Mode -eq "jp" -and $Candidate -notmatch "[\u3400-\u9fff]") { return $false }
  $id = "$Mode`t$English`t$Candidate"
  if ($Seen.Contains($id)) { return $false }
  $Seen.Add($id) | Out-Null
  $Writer.WriteLine("$Mode`t$English`t$Candidate`t$Weight`t$Comment")
  return $true
}

function Convert-JMdict([string]$InputFile, [string]$OutputFile) {
  if ((Test-Path $OutputFile) -and (Get-Item $OutputFile).Length -gt 0 -and !$Force) {
    Write-Host "Using cached $OutputFile"
    return
  }

  $seen = [System.Collections.Generic.HashSet[string]]::new()
  $writer = [System.IO.StreamWriter]::new($OutputFile, $false, [System.Text.UTF8Encoding]::new($false))
  try {
    $writer.WriteLine("# mode`tenglish`tcandidate`tweight`tcomment")
    $count = 0

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Parse
    $settings.XmlResolver = $null
    $settings.IgnoreWhitespace = $true
    $reader = [System.Xml.XmlReader]::Create($InputFile, $settings)
    try {
      $kebs = [System.Collections.Generic.List[string]]::new()
      $rebs = [System.Collections.Generic.List[string]]::new()
      $glosses = [System.Collections.Generic.List[string]]::new()
      $inEntry = $false

      while ($reader.Read()) {
        if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
          switch ($reader.Name) {
            "entry" {
              $inEntry = $true
              $kebs.Clear()
              $rebs.Clear()
              $glosses.Clear()
            }
            "keb" {
              if ($inEntry) {
                $value = $reader.ReadElementContentAsString()
                if ($value) { $kebs.Add($value) }
              }
            }
            "reb" {
              if ($inEntry) {
                $value = $reader.ReadElementContentAsString()
                if ($value) { $rebs.Add($value) }
              }
            }
            "gloss" {
              if ($inEntry) {
                $value = $reader.ReadElementContentAsString()
                if ($value) { $glosses.Add($value) }
              }
            }
          }
        } elseif ($reader.NodeType -eq [System.Xml.XmlNodeType]::EndElement -and $reader.Name -eq "entry") {
          $candidates = if ($kebs.Count -gt 0) { $kebs } else { $rebs }
          $rank = 0
          foreach ($gloss in $glosses) {
            $rank++
            foreach ($key in (Get-EnglishKeys $gloss)) {
              foreach ($candidate in ($candidates | Select-Object -First 4)) {
                if (Add-Row $writer $seen "jp" $key $candidate ([Math]::Max(10, 900 - $rank)) "jmdict") {
                  $count++
                  if ($count -ge $MaxRowsPerMode) { return }
                }
              }
            }
          }
          $inEntry = $false
        }
      }
    } finally {
      $reader.Dispose()
    }
  } finally {
    $writer.Dispose()
  }
}

function Convert-Cedict([string]$InputFile, [string]$OutputFile) {
  if ((Test-Path $OutputFile) -and (Get-Item $OutputFile).Length -gt 0 -and !$Force) {
    Write-Host "Using cached $OutputFile"
    return
  }

  $seen = [System.Collections.Generic.HashSet[string]]::new()
  $writer = [System.IO.StreamWriter]::new($OutputFile, $false, [System.Text.UTF8Encoding]::new($false))
  try {
    $writer.WriteLine("# mode`tenglish`tcandidate`tweight`tcomment")
    $counts = @{ zh = 0; hk = 0 }
    foreach ($line in [System.IO.File]::ReadLines($InputFile, [System.Text.Encoding]::UTF8)) {
      if (!$line -or $line.StartsWith("#")) { continue }
      $match = [regex]::Match($line, "^(?<trad>\S+)\s+(?<simp>\S+)\s+\[(?<pinyin>[^\]]+)\]\s+/(?<gloss>.*)/$")
      if (!$match.Success) { continue }
      $trad = $match.Groups["trad"].Value
      $simp = $match.Groups["simp"].Value
      $rank = 0
      foreach ($gloss in ($match.Groups["gloss"].Value -split "/")) {
        $rank++
        foreach ($key in (Get-EnglishKeys $gloss)) {
          $weight = [Math]::Max(10, 900 - $rank)
          if ($counts.zh -lt $MaxRowsPerMode) {
            if (Add-Row $writer $seen "zh" $key $simp $weight "cc-cedict") { $counts.zh++ }
          }
          if ($counts.hk -lt $MaxRowsPerMode) {
            if (Add-Row $writer $seen "hk" $key $trad $weight "cc-cedict") { $counts.hk++ }
          }
        }
      }
      if ($counts.zh -ge $MaxRowsPerMode -and $counts.hk -ge $MaxRowsPerMode) { return }
    }
  } finally {
    $writer.Dispose()
  }
}

$jmdictGz = Join-Path $cacheDir "JMdict_e.gz"
$jmdictTxt = Join-Path $cacheDir "JMdict_e"
$cedictGz = Join-Path $cacheDir "cedict_ts.u8.gz"
$cedictTxt = Join-Path $cacheDir "cedict_ts.u8"

Write-Host "Downloading JMdict_e..."
Download-File $JpUrl $jmdictGz
Expand-Gzip $jmdictGz $jmdictTxt
Convert-JMdict $jmdictTxt (Join-Path $outDir "jmdict.tsv")
Remove-Item -LiteralPath (Join-Path $outDir "edict2.tsv") -Force -ErrorAction SilentlyContinue

Write-Host "Downloading CC-CEDICT..."
Download-File $CedictUrl $cedictGz
Expand-Gzip $cedictGz $cedictTxt
Convert-Cedict $cedictTxt (Join-Path $outDir "cc-cedict.tsv")

Write-Host "Large dictionary TSV files are ready in $outDir"
