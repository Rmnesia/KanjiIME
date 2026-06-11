param(
  [string]$SdkDir = "build/android-sdk",
  [string]$CommandLineToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-14742923_latest.zip",
  [string]$BuildToolsVersion = "36.0.0",
  [string]$NdkVersion = "28.0.13004108",
  [string]$CmakeVersion = "3.31.6"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$sdk = Join-Path $root $SdkDir
$downloads = Join-Path $root "build/downloads"
$zip = Join-Path $downloads "commandlinetools-win.zip"
$cmdlineRoot = Join-Path $sdk "cmdline-tools"
$latest = Join-Path $cmdlineRoot "latest"
$sdkmanager = Join-Path $latest "bin/sdkmanager.bat"

New-Item -ItemType Directory -Force -Path $downloads | Out-Null
New-Item -ItemType Directory -Force -Path $cmdlineRoot | Out-Null

if (!(Test-Path $sdkmanager)) {
  if (!(Test-Path $zip)) {
    Write-Host "Downloading Android command-line tools..."
    Invoke-WebRequest -Uri $CommandLineToolsUrl -OutFile $zip
  }

  $extract = Join-Path $downloads "cmdline-tools-extract"
  Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $latest -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
  New-Item -ItemType Directory -Force -Path $latest | Out-Null
  Copy-Item -Path (Join-Path $extract "cmdline-tools\*") -Destination $latest -Recurse -Force
}

$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk

Write-Host "Accepting Android SDK licenses..."
"y`ny`ny`ny`ny`ny`ny`ny`ny`ny`n" | & $sdkmanager --sdk_root=$sdk --licenses | Out-Host

Write-Host "Installing Android build-tools;$BuildToolsVersion, ndk;$NdkVersion, cmake;$CmakeVersion..."
& $sdkmanager --sdk_root=$sdk "build-tools;$BuildToolsVersion" "platform-tools" "ndk;$NdkVersion" "cmake;$CmakeVersion"
if ($LASTEXITCODE -ne 0) {
  throw "sdkmanager failed to install Android build-tools."
}

Write-Host "Android SDK ready at $sdk"
