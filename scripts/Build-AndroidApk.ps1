param(
  [string]$TrimeRepo = "https://github.com/osfans/trime.git",
  [string]$WorkDir = "build/trime",
  [string]$OutputDir = "dist/android",
  [switch]$SkipLargeDictionaryRefresh
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$work = Join-Path $root $WorkDir
$out = Join-Path $root $OutputDir

if (!$env:ANDROID_HOME -and !$env:ANDROID_SDK_ROOT) {
  $localSdk = Join-Path $root "build/android-sdk"
  if (Test-Path $localSdk) {
    $env:ANDROID_HOME = $localSdk
    $env:ANDROID_SDK_ROOT = $localSdk
  } else {
    throw "Android SDK not found. Run scripts/Install-AndroidBuildTools.ps1, set ANDROID_HOME or ANDROID_SDK_ROOT, or create local.properties with sdk.dir in the cloned Trime project."
  }
}

if (!$SkipLargeDictionaryRefresh) {
  & (Join-Path $root "tools/Download-LargeDictionaries.ps1")
}
& (Join-Path $root "tools/Build-Dictionaries.ps1")

if (!(Test-Path $work)) {
  git clone --depth 1 $TrimeRepo $work
} else {
  git -C $work pull --ff-only
}

$localProperties = Join-Path $work "local.properties"
$sdkPath = ($env:ANDROID_HOME -replace "\\", "\\")
Set-Content -LiteralPath $localProperties -Value "sdk.dir=$sdkPath" -Encoding ASCII

& (Join-Path $root "scripts/Patch-AndroidBranding.ps1") -TrimeDir $WorkDir

$toolsDir = Join-Path $root "build/tools"
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
$python3CmdShim = Join-Path $toolsDir "python3.cmd"
if (Test-Path $python3CmdShim) {
  Remove-Item -LiteralPath $python3CmdShim -Force
}
$python3ExeShim = Join-Path $toolsDir "python3.exe"
if (!(Test-Path $python3ExeShim)) {
  $python = Get-Command python -ErrorAction SilentlyContinue
  if (!$python) {
    throw "python3.exe was not found in $toolsDir and python is not available on PATH."
  }
  Copy-Item -LiteralPath $python.Source -Destination $python3ExeShim -Force
}
$env:PATH = "$toolsDir;$env:PATH"
$env:BUILD_ABI = "arm64-v8a"

$assetCandidates = @(
  (Join-Path $work "app/src/main/assets/shared"),
  (Join-Path $work "app/src/main/assets/rime")
)

$assetDir = $assetCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (!$assetDir) {
  $assetDir = Join-Path $work "app/src/main/assets/rime"
  New-Item -ItemType Directory -Force -Path $assetDir | Out-Null
}

Copy-Item -LiteralPath (Join-Path $root "rime/default.custom.yaml") -Destination $assetDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/trime.custom.yaml") -Destination $assetDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_jp.schema.yaml") -Destination $assetDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_zh.schema.yaml") -Destination $assetDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_hk.schema.yaml") -Destination $assetDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_jp.dict.yaml") -Destination $assetDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_zh.dict.yaml") -Destination $assetDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_hk.dict.yaml") -Destination $assetDir -Force

Push-Location $work
try {
  if (Test-Path ".\gradlew.bat") {
    .\gradlew.bat assembleDebug
    if ($LASTEXITCODE -ne 0) {
      throw "Gradle assembleDebug failed."
    }
  } else {
    gradle assembleDebug
    if ($LASTEXITCODE -ne 0) {
      throw "Gradle assembleDebug failed."
    }
  }
} finally {
  Pop-Location
}

New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem -Path $work -Recurse -Filter "*.apk" |
  Where-Object { $_.FullName -match "\\build\\outputs\\apk\\" } |
  Copy-Item -Destination $out -Force

Write-Host "Copied APK files to $out"
