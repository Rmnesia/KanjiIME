param(
  [string]$OutputDir = "dist/android",
  [string]$Keystore = "build/android-debug.keystore",
  [string]$KeyAlias = "kanjiime",
  [string]$StorePass = "kanjiime",
  [string]$KeyPass = "kanjiime",
  [ValidateSet("arm64-v8a", "armeabi-v7a", "x86", "x86_64")]
  [string]$Abi = "arm64-v8a",
  [switch]$SkipLargeDictionaryRefresh
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$out = Join-Path $root $OutputDir
$work = Join-Path $root "build/android-patched"
$unsigned = Join-Path $work "KanjiIME-Trime-unsigned.apk"
$aligned = Join-Path $work "KanjiIME-Trime-aligned.apk"
$signed = Join-Path $out "KanjiIME-Trime-$Abi-patched.apk"
$download = Join-Path $work "trime-$Abi-release.apk"
$keystorePath = Join-Path $root $Keystore

if (!$SkipLargeDictionaryRefresh) {
  & (Join-Path $root "tools/Download-LargeDictionaries.ps1")
}
& (Join-Path $root "tools/Build-Dictionaries.ps1")

New-Item -ItemType Directory -Force -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $out | Out-Null

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/osfans/trime/releases/latest"
$asset = $release.assets |
  Where-Object { $_.name -match [regex]::Escape($Abi) -and $_.name -match "release\.apk$" } |
  Select-Object -First 1

if (!$asset) {
  throw "Could not find a Trime APK asset in the latest GitHub release."
}

Write-Host "Downloading Trime APK from $($asset.browser_download_url)"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $download
Copy-Item -LiteralPath $download -Destination $unsigned -Force

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($unsigned, [System.IO.Compression.ZipArchiveMode]::Update)
try {
  @($zip.Entries | Where-Object { $_.FullName -match "^META-INF/" }) | ForEach-Object { $_.Delete() }

  Get-ChildItem -LiteralPath (Join-Path $root "rime") -Filter "*.yaml" | ForEach-Object {
    $entryName = "assets/shared/$($_.Name)"
    $existing = $zip.GetEntry($entryName)
    if ($existing) { $existing.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entryName) | Out-Null
  }
} finally {
  $zip.Dispose()
}

function Find-AndroidBuildTool([string]$Name) {
  $roots = @(
    $env:ANDROID_HOME,
    $env:ANDROID_SDK_ROOT,
    (Join-Path $env:LOCALAPPDATA "Android\Sdk")
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

  foreach ($rootPath in $roots) {
    $match = Get-ChildItem -LiteralPath (Join-Path $rootPath "build-tools") -Recurse -Filter $Name -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($match) { return $match.FullName }
  }

  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

$zipalign = Find-AndroidBuildTool "zipalign.exe"
if (!$zipalign) { $zipalign = Find-AndroidBuildTool "zipalign" }
$apksigner = Find-AndroidBuildTool "apksigner.bat"
if (!$apksigner) { $apksigner = Find-AndroidBuildTool "apksigner" }

if (!$zipalign -or !$apksigner) {
  throw "Android build-tools are required for an installable APK. Install Android SDK build-tools and set ANDROID_HOME or ANDROID_SDK_ROOT. Missing: zipalign=$zipalign apksigner=$apksigner"
}

if (!(Test-Path $keystorePath)) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $keystorePath) | Out-Null
  keytool -genkeypair `
    -keystore $keystorePath `
    -storepass $StorePass `
    -keypass $KeyPass `
    -alias $KeyAlias `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -dname "CN=KanjiIME, OU=KanjiIME, O=KanjiIME, L=Local, ST=Local, C=US"
}

Remove-Item -LiteralPath $aligned, $signed -Force -ErrorAction SilentlyContinue
& $zipalign -p -f 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) {
  throw "zipalign failed."
}

& $apksigner sign `
  --ks $keystorePath `
  --ks-pass "pass:$StorePass" `
  --key-pass "pass:$KeyPass" `
  --out $signed `
  $aligned
if ($LASTEXITCODE -ne 0) {
  throw "apksigner failed."
}

& $apksigner verify --verbose $signed
if ($LASTEXITCODE -ne 0) {
  throw "apksigner verification failed."
}

if (!(Test-Path $signed)) {
  throw "Failed to create $signed"
}

Write-Host "Created $signed"
