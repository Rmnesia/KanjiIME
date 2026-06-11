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
Get-ChildItem -LiteralPath $assetDir -Filter "luna*" -ErrorAction SilentlyContinue |
  Remove-Item -Force

$defaultYaml = @'
# KanjiIME default Rime configuration for Android.
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
Set-Content -LiteralPath (Join-Path $assetDir "default.yaml") -Value $defaultYaml -Encoding UTF8

$dataManager = Join-Path $work "app/src/main/java/com/osfans/trime/data/base/DataManager.kt"
if (Test-Path $dataManager) {
  $text = Get-Content -LiteralPath $dataManager -Raw -Encoding UTF8
  $newPatch = @'
    private const val SCHEMA_LIST_CUSTOM_PATCH = """
      patch:
        schema_list:
          - schema: kanji_en_jp
          - schema: kanji_en_zh
          - schema: kanji_en_hk
        menu/page_size: 7
    """
'@
  $text = [regex]::Replace(
    $text,
    '(?s)    private const val SCHEMA_LIST_CUSTOM_PATCH = """\s*.*?\s*    """',
    [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newPatch.TrimEnd("`r", "`n") }
  )
  $text = $text -replace 'val defaultDataDir = File\(Environment\.getExternalStorageDirectory\(\), "rime"\)', 'val defaultDataDir = File(appContext.getExternalFilesDir(null), "user")'
  $newSyncTail = @'
        ResourceUtils.copyFile(DATA_CHECKSUMS_NAME, dataDir.resolve(DATA_CHECKSUMS_NAME).absolutePath)

        val configuredDataDir = prefs.profile.userDataDir.getValue()
        if (configuredDataDir != defaultDataDir.absolutePath) {
            prefs.profile.userDataDir.setValue(defaultDataDir.absolutePath)
        }

        val defaultConfig = userDataDir.resolve("default.yaml")
        defaultConfig.writeText(
            """
            config_version: "2026-06-11"
            schema_list:
              - schema: kanji_en_jp
              - schema: kanji_en_zh
              - schema: kanji_en_hk
            menu:
              page_size: 7
            switcher:
              caption: "KanjiIME"
            """.trimIndent(),
        )

        val userConfig = userDataDir.resolve("user.yaml")
        if (!userConfig.exists()) {
            userConfig.writeText("var:\n  option:\n    ascii_mode: false\n")
        }

        val custom = userDataDir.resolve(DEFAULT_CUSTOM_FILE_NAME)
        val existingCustom = custom.takeIf { it.exists() }?.readText().orEmpty()
        if (!custom.exists() || !existingCustom.contains("kanji_en_jp") || existingCustom.contains("luna_pinyin")) {
            custom.writeText(SCHEMA_LIST_CUSTOM_PATCH.trimIndent())
        }
'@
  $text = [regex]::Replace(
    $text,
    '(?s)        ResourceUtils\.copyFile\(DATA_CHECKSUMS_NAME, dataDir\.resolve\(DATA_CHECKSUMS_NAME\)\.absolutePath\)\s*.*?(?=\r?\n        Timber\.d\("Synced!"\))',
    [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newSyncTail.TrimEnd("`r", "`n") }
  )
  Set-Content -LiteralPath $dataManager -Value $text -Encoding UTF8
}

$commonKeyboard = Join-Path $work "app/src/main/java/com/osfans/trime/ime/keyboard/CommonKeyboardActionListener.kt"
if (Test-Path $commonKeyboard) {
  $text = Get-Content -LiteralPath $commonKeyboard -Raw -Encoding UTF8
  $old = @'
            private fun handleLanguageSwitch(action: KeyAction) {
                when {
                    action.select == ".next" -> service.switchToNextIme()
                    action.select.isNotEmpty() -> service.switchToPrevIme()
                    else -> inputMethodManager.showInputMethodPicker()
                }
            }
'@
  $new = @'
            private fun handleLanguageSwitch(action: KeyAction) {
                when {
                    action.select == ".next" -> service.switchToNextIme()
                    action.select == ".last" -> service.switchToPrevIme()
                    action.select.isNotEmpty() -> {
                        rime.launchOnReady { api ->
                            service.lifecycleScope.launch {
                                api.selectSchema(action.select)
                            }
                        }
                    }
                    else -> inputMethodManager.showInputMethodPicker()
                }
            }
'@
  if ($text.Contains($old)) {
    $text = $text.Replace($old, $new)
  }
  Set-Content -LiteralPath $commonKeyboard -Value $text -Encoding UTF8
}

$trimeYaml = Join-Path $assetDir "trime.yaml"
if (Test-Path $trimeYaml) {
  $text = Get-Content -LiteralPath $trimeYaml -Raw -Encoding UTF8
  if ($text -notmatch "KanjiIME_schema") {
    $text = $text -replace "(?m)^(\s*)Schema_switch:\s*\{.*$", "`$1Schema_switch: {label: Lang, send: Menu}`r`n`$1KanjiIME_jp: {label: JP, send: LANGUAGE_SWITCH, select: kanji_en_jp}`r`n`$1KanjiIME_zh: {label: ZH, send: LANGUAGE_SWITCH, select: kanji_en_zh}`r`n`$1KanjiIME_hk: {label: HK, send: LANGUAGE_SWITCH, select: kanji_en_hk}`r`n`$1KanjiIME_schema: {label: Lang, send: Menu}"
  }
  $text = $text -replace "\{click: Mode_switch, long_click: Menu, width: 15\}", "{click: KanjiIME_schema, long_click: Mode_switch, width: 15}"
  $text = $text -replace "\{click: Mode_switch, long_click: Menu\}", "{click: KanjiIME_schema, long_click: Mode_switch}"
  Set-Content -LiteralPath $trimeYaml -Value $text -Encoding UTF8
}

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
