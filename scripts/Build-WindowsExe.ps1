param(
  [string]$WeaselReleaseUrl = "",
  [string]$OutputDir = "dist/windows",
  [switch]$SkipLargeDictionaryRefresh
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$dist = Join-Path $root $OutputDir
$payload = Join-Path $dist "payload"
$payloadRime = Join-Path $payload "rime"
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

$weaselInstaller = Join-Path $payload "weasel-installer.exe"
if (!$WeaselReleaseUrl) {
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/rime/weasel/releases/latest"
  $asset = $release.assets |
    Where-Object { $_.name -match "installer.*\.exe$" -or $_.name -match "\.exe$" } |
    Select-Object -First 1

  if (!$asset) {
    throw "Could not find a Weasel installer asset in the latest GitHub release."
  }

  $WeaselReleaseUrl = $asset.browser_download_url
}

Write-Host "Downloading Weasel installer from $WeaselReleaseUrl"
Invoke-WebRequest -Uri $WeaselReleaseUrl -OutFile $weaselInstaller

# IExpress cannot preserve subdirectories listed in SourceFiles reliably, so flatten
# Rime files into the package and the installer copies from its extracted rime folder
# when run from the generated package directory.
Copy-Item -Path (Join-Path $payloadRime "*.yaml") -Destination $payload -Force

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
