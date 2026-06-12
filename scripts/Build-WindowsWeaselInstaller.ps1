param(
  [string]$WeaselDir = "build/weasel",
  [string]$WeaselSourceDir = "",
  [string]$OutputDir = "dist/windows",
  [switch]$SkipLargeDictionaryRefresh
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$weasel = Join-Path $root $WeaselDir
$outDir = Join-Path $root $OutputDir
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (!(Test-Path $weasel)) {
  git clone --depth 1 https://github.com/rime/weasel.git $weasel
}

if (!$SkipLargeDictionaryRefresh) {
  & (Join-Path $root "tools/Download-LargeDictionaries.ps1")
}
& (Join-Path $root "tools/Build-Dictionaries.ps1")

if (!$WeaselSourceDir) {
  $weaselRoots = @(
    (Join-Path ${env:ProgramFiles} "Rime"),
    (Join-Path ${env:ProgramFiles(x86)} "Rime")
  ) | Where-Object { $_ -and (Test-Path $_) }

  $weaselSetup = $weaselRoots |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter "WeaselSetup.exe" -ErrorAction SilentlyContinue } |
    Where-Object { $_.FullName -notmatch "\\weasel-kanjiime\\" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (!$weaselSetup) {
    throw "Weasel program files were not found. Install official Rime Weasel once on this build machine, or pass -WeaselSourceDir <folder containing WeaselSetup.exe>."
  }

  $WeaselSourceDir = $weaselSetup.Directory.FullName
}

$source = Resolve-Path $WeaselSourceDir
foreach ($required in @("WeaselSetup.exe", "WeaselDeployer.exe", "WeaselServer.exe", "weasel.dll", "weasel.ime", "rime.dll")) {
  if (!(Test-Path (Join-Path $source $required))) {
    throw "Invalid Weasel source directory: missing $required in $source"
  }
}

$weaselOutput = Join-Path $weasel "output"
$patchedNsi = Join-Path $weaselOutput "install-kanjiime.nsi"
$archives = Join-Path $weaselOutput "archives"
New-Item -ItemType Directory -Force -Path $weaselOutput, $archives | Out-Null

Write-Host "Preparing official Weasel installer payload from $source"
Copy-Item -Path (Join-Path $source "*") -Destination $weaselOutput -Recurse -Force

$dataDir = Join-Path $weaselOutput "data"
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$defaultYaml = @'
# KanjiIME default Rime configuration.
config_version: "2026-06-11"
schema_list:
  - schema: kanji_en_jp
  - schema: kanji_en_zh
  - schema: kanji_en_hk
menu:
  page_size: 7
switcher:
  caption: "KanjiIME"
  hotkeys:
    - F4
    - Control+grave
    - Control+Shift+grave
'@
Set-Content -LiteralPath (Join-Path $dataDir "default.yaml") -Value $defaultYaml -Encoding UTF8

Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_jp.schema.yaml") -Destination $dataDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_zh.schema.yaml") -Destination $dataDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_hk.schema.yaml") -Destination $dataDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_jp.dict.yaml") -Destination $dataDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_zh.dict.yaml") -Destination $dataDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/kanji_en_hk.dict.yaml") -Destination $dataDir -Force

$kanjiUserDir = Join-Path $weaselOutput "kanjiime-user"
New-Item -ItemType Directory -Force -Path $kanjiUserDir | Out-Null
Copy-Item -LiteralPath (Join-Path $root "rime/default.custom.yaml") -Destination $kanjiUserDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/weasel.custom.yaml") -Destination $kanjiUserDir -Force
Copy-Item -LiteralPath (Join-Path $root "rime/user.yaml") -Destination $kanjiUserDir -Force

$nsi = Get-Content -LiteralPath (Join-Path $weaselOutput "install.nsi") -Raw -Encoding UTF8
$compatibleInitBlock = @'
  ; KanjiIME NSIS compatibility: choose 64-bit files on native 64-bit Windows.
  ${If} ${IsNativeAMD64}
    StrCpy $INSTDIR "$PROGRAMFILES64\Rime"
  ${Else}
    StrCpy $INSTDIR "$PROGRAMFILES\Rime"
  ${Endif}
skip:
'@
$nsi = [regex]::Replace(
  $nsi,
  '(?s)  ; install x64 build for NativeARM64_WINDOWS11 and NativeAMD64_WINDOWS11\r?\n  \$\{If\} \$\{AtLeastWin11\} ; Windows 11 and above.*?  \$\{Endif\}\r?\nskip:',
  [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $compatibleInitBlock }
)

$compatibleFileBlock = @'
  ; KanjiIME bundles the x64 Weasel runtime.
  File "WeaselDeployer.exe"
  File "WeaselServer.exe"
  File "rime.dll"
  File "WinSparkle.dll"
'@
$nsi = [regex]::Replace(
  $nsi,
  '(?s)  ; install x64 build for NativeARM64_WINDOWS11 and NativeAMD64_WINDOWS11\r?\n  \$\{If\} \$\{AtLeastWin11\} ; Windows 11 and above.*?  \$\{Endif\}\r?\n(?=\r?\n  File "WeaselSetup\.exe")',
  [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $compatibleFileBlock }
)

$minimalPages = @'
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
'@
$nsi = [regex]::Replace(
  $nsi,
  '(?s)!insertmacro MUI_PAGE_LICENSE.*?!insertmacro MUI_UNPAGE_FINISH',
  [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $minimalPages }
)

$nsi = [regex]::Replace(
  $nsi,
  '(?s)!insertmacro MUI_LANGUAGE "TradChinese".*?(?=!insertmacro MUI_LANGUAGE "English")',
  ''
)

$nsi = [regex]::Replace($nsi, '(?m)^Name\s+".*?\$\{WEASEL_VERSION\}"', 'Name "KanjiIME ${WEASEL_VERSION}"')
$nsi = $nsi -replace 'OutFile "archives\\weasel-\$\{PRODUCT_VERSION\}-installer\.exe"', ('OutFile "archives\KanjiIME-Weasel-Setup-' + $stamp + '.exe"')
$nsi = [regex]::Replace($nsi, '(?m)^VIAddVersionKey /LANG=2052 "ProductName" ".*?"', 'VIAddVersionKey /LANG=2052 "ProductName" "KanjiIME"')
$nsi = $nsi -replace 'VIAddVersionKey /LANG=2052 "FileDescription" "小狼毫輸入法"', 'VIAddVersionKey /LANG=2052 "FileDescription" "KanjiIME input method"'
$nsi = [regex]::Replace($nsi, '(?m)^VIAddVersionKey /LANG=2052 "FileDescription" ".*?"', 'VIAddVersionKey /LANG=2052 "FileDescription" "KanjiIME input method"')

$englishStrings = [ordered]@{
  DISPLAYNAME = "KanjiIME"
  LNKFORMANUAL = "KanjiIME Manual"
  LNKFORSETTING = "KanjiIME Settings"
  LNKFORDICT = "KanjiIME Dictionary Manager"
  LNKFORSYNC = "KanjiIME Sync User Profile"
  LNKFORDEPLOY = "KanjiIME Deploy"
  LNKFORSERVER = "KanjiIME Server"
  LNKFORUSERFOLDER = "KanjiIME User Folder"
  LNKFORAPPFOLDER = "KanjiIME App Folder"
  LNKFORUPDATER = "KanjiIME Check for Updates"
  LNKFORSETUP = "KanjiIME Installation Options"
  LNKFORUNINSTALL = "Uninstall KanjiIME"
  CONFIRMATION = 'Before installation, please uninstall the old version of KanjiIME or Weasel.$\n$\nPress OK to remove the old version, or Cancel to abort installation.'
  SYSTEMVERSIONNOTOK = "Your system is not supported. Minimum system required: Windows 8.1."
  AUTOCHKUPDATE = "Automatically check for updates?"
}
foreach ($lang in @("LANG_TRADCHINESE", "LANG_SIMPCHINESE", "LANG_ENGLISH")) {
  foreach ($key in $englishStrings.Keys) {
    $value = $englishStrings[$key]
    $pattern = "(?m)^LangString $key \`$\{$lang\} .*$"
    $replacement = "LangString $key " + '${' + $lang + '} "' + $value + '"'
    $nsi = [regex]::Replace($nsi, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement })
  }
}

$nsi = [regex]::Replace(
  $nsi,
  '(?s)  StrCpy\s+\$0\s+"Upgrade"\r?\n  IfSilent uninst 0\r?\n  MessageBox MB_OKCANCEL\|MB_ICONINFORMATION "\$\(CONFIRMATION\)" IDOK uninst\r?\n  Abort\r?\n\r?\nuninst:',
  [System.Text.RegularExpressions.MatchEvaluator]{ param($m) "  StrCpy `$0 `"Upgrade`"`r`n  GoTo uninst`r`n`r`nuninst:" }
)

$nsi = [regex]::Replace(
  $nsi,
  '(?s)  ; option CheckForUpdates\r?\n  IfSilent DisableAutoCheckUpdate.*?  end:',
  '  ; KanjiIME: disable update checks by default without prompting.' + "`r`n  WriteRegStr HKCU `"Software\Rime\Weasel\Updates`" `"CheckForUpdates`" `"0`""
)
$nsi = $nsi -replace 'WriteRegStr HKLM "\$\{REG_UNINST_KEY\}" "DisplayName" "\$\(DISPLAYNAME\)"', 'WriteRegStr HKLM "${REG_UNINST_KEY}" "DisplayName" "KanjiIME"'
$nsi = $nsi -replace 'WriteRegStr HKLM "\$\{REG_UNINST_KEY\}" "Publisher" "式恕堂"', 'WriteRegStr HKLM "${REG_UNINST_KEY}" "Publisher" "KanjiIME / Rime Weasel"'

$copyUserBlock = @'

  ; KanjiIME user data defaults
  SetShellVarContext current
  SetOutPath "$APPDATA\Rime"
  File "kanjiime-user\default.custom.yaml"
  File "kanjiime-user\weasel.custom.yaml"
  File "kanjiime-user\user.yaml"
  SetShellVarContext all
'@
$nsi = $nsi -replace '(?m)^  SetOutPath \$INSTDIR\r?\n\r?\n  ; test /T flag for zh_TW locale', ('  SetOutPath $INSTDIR' + $copyUserBlock + "`r`n`r`n  ; test /T flag for zh_TW locale")

$silentSetupBlock = @'
  ; KanjiIME: install Weasel silently, then apply preferences one command at a time.
  ExecWait '"$INSTDIR\WeaselSetup.exe" /s'
  ExecWait '"$INSTDIR\WeaselSetup.exe" /le'
  ExecWait '"$INSTDIR\WeaselSetup.exe" /du'
  ExecWait '"$INSTDIR\WeaselSetup.exe" /toggleascii'
'@
$nsi = [regex]::Replace(
  $nsi,
  '(?s)  ; test /T flag for zh_TW locale\r?\n  StrCpy \$R2 "/i"\r?\n  \$\{GetParameters\} \$R0\r?\n  ClearErrors\r?\n  \$\{GetOptions\} \$R0 "/S" \$R1\r?\n  IfErrors \+2 0\r?\n  StrCpy \$R2 "/s"\r?\n  \$\{GetOptions\} \$R0 "/T" \$R1\r?\n  IfErrors \+2 0\r?\n  StrCpy \$R2 "/t"\r?\n\r?\n  ExecWait ''"\$INSTDIR\\WeaselSetup\.exe" \$R2''',
  [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $silentSetupBlock }
)

Set-Content -LiteralPath $patchedNsi -Value $nsi -Encoding UTF8

$makensis = Get-Command makensis.exe -ErrorAction SilentlyContinue
if (!$makensis) {
  $candidates = @(
    "${env:ProgramFiles(x86)}\NSIS\Bin\makensis.exe",
    "${env:ProgramFiles}\NSIS\Bin\makensis.exe"
  )
  $makensisPath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (!$makensisPath) {
    Write-Host "NSIS not found. Installing NSIS using Weasel's helper script..."
    Push-Location $weasel
    try {
      & .\install_nsis.bat
    } finally {
      Pop-Location
    }
    $makensisPath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  }
  if (!$makensisPath) {
    throw "makensis.exe was not found after attempting NSIS installation."
  }
} else {
  $makensisPath = $makensis.Source
}

Push-Location $weaselOutput
try {
  & $makensisPath `
    /DWEASEL_VERSION=0.17.4 `
    /DWEASEL_BUILD=0 `
    /DPRODUCT_VERSION=0.17.4.0 `
    $patchedNsi
  if ($LASTEXITCODE -ne 0) {
    throw "makensis failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}

$built = Join-Path $archives ("KanjiIME-Weasel-Setup-$stamp.exe")
if (!(Test-Path $built)) {
  throw "Expected installer was not created: $built"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$final = Join-Path $outDir ("KanjiIME-Weasel-Setup-$stamp.exe")
Copy-Item -LiteralPath $built -Destination $final -Force
Write-Host "Created $final"
