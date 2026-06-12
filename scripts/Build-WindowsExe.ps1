param(
  [string]$OutputDir = "dist/windows",
  [string]$WeaselSourceDir = "",
  [switch]$SkipLargeDictionaryRefresh
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$dist = Join-Path $root $OutputDir
$payload = Join-Path $dist "payload"
$payloadRime = Join-Path $payload "rime"
$payloadWeasel = Join-Path $payload "weasel"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$targetExe = Join-Path $dist "KanjiIME-Windows-Setup-$stamp.exe"
$payloadZip = Join-Path $dist "payload.zip"

if (!$SkipLargeDictionaryRefresh) {
  & (Join-Path $root "tools/Download-LargeDictionaries.ps1")
}
& (Join-Path $root "tools/Build-Dictionaries.ps1")

Remove-Item -LiteralPath $targetExe -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $payload -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $payloadRime | Out-Null
New-Item -ItemType Directory -Force -Path $payloadWeasel | Out-Null

Copy-Item -LiteralPath (Join-Path $root "rime/default.custom.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/user.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/weasel.custom.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/trime.custom.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_jp.schema.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_zh.schema.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_hk.schema.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_jp.dict.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_zh.dict.yaml") -Destination $payloadRime
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_hk.dict.yaml") -Destination $payloadRime

if (!$WeaselSourceDir) {
  $weaselRoots = @(
    (Join-Path ${env:ProgramFiles} "Rime"),
    (Join-Path ${env:ProgramFiles(x86)} "Rime")
  ) | Where-Object { $_ -and (Test-Path $_) }

  $weaselSetup = $weaselRoots |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter "WeaselSetup.exe" -ErrorAction SilentlyContinue } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (!$weaselSetup) {
    throw "Weasel program files were not found. Install Rime Weasel once on this build machine, or pass -WeaselSourceDir <folder containing WeaselSetup.exe>."
  }

  $WeaselSourceDir = $weaselSetup.Directory.FullName
}

$weaselSourcePath = Resolve-Path $WeaselSourceDir
if (!(Test-Path (Join-Path $weaselSourcePath "WeaselSetup.exe")) -or !(Test-Path (Join-Path $weaselSourcePath "WeaselDeployer.exe"))) {
  throw "Invalid Weasel source directory: $weaselSourcePath. Expected WeaselSetup.exe and WeaselDeployer.exe."
}

Write-Host "Bundling Weasel program files from $weaselSourcePath"
Copy-Item -Path (Join-Path $weaselSourcePath "*") -Destination $payloadWeasel -Recurse -Force

Remove-Item -LiteralPath $payloadZip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $payload "*") -DestinationPath $payloadZip -Force

$compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (!(Test-Path $compiler)) {
  $compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

if (!(Test-Path $compiler)) {
  throw "C# compiler was not found. Expected .NET Framework csc.exe."
}

$source = Join-Path $root "packaging/windows/KanjiImeInstaller.cs"
$manifest = Join-Path $root "packaging/windows/app.manifest"
& $compiler `
  /nologo `
  /target:winexe `
  /platform:anycpu `
  /out:$targetExe `
  /win32manifest:$manifest `
  /resource:$payloadZip,payload.zip `
  /reference:System.Windows.Forms.dll `
  /reference:System.IO.Compression.dll `
  /reference:System.IO.Compression.FileSystem.dll `
  $source

if (!(Test-Path $targetExe)) {
  throw "Failed to create $targetExe"
}

Write-Host "Created $targetExe"
$global:LASTEXITCODE = 0
