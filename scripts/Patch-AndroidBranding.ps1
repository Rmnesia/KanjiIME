param(
  [string]$TrimeDir = "build/trime"
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$work = Join-Path $root $TrimeDir
$res = Join-Path $work "app/src/main/res"
$defaultStrings = Join-Path $res "values/strings.xml"

if (!(Test-Path $res)) {
  throw "Trime Android resources not found: $res"
}

if (!(Test-Path $defaultStrings)) {
  throw "Default Android strings not found: $defaultStrings"
}

function Set-StringValue([string]$File, [string]$Name, [string]$Value, [switch]$RawXml) {
  if (!(Test-Path $File)) { return }
  $text = Get-Content -LiteralPath $File -Raw -Encoding UTF8
  $escaped = if ($RawXml) { $Value } else { [System.Security.SecurityElement]::Escape($Value) }
  $pattern = "<string name=`"$([regex]::Escape($Name))`">.*?</string>"
  if ($text -match $pattern) {
    $text = [regex]::Replace($text, $pattern, "<string name=`"$Name`">$escaped</string>")
  } else {
    $text = $text -replace "</resources>", "    <string name=`"$Name`">$escaped</string>`r`n</resources>"
  }
  Set-Content -LiteralPath $File -Value $text -Encoding UTF8
}

Get-ChildItem -LiteralPath $res -Directory -Filter "values*" | ForEach-Object {
  $strings = Join-Path $_.FullName "strings.xml"
  if (!(Test-Path $strings)) { return }

  if ($_.Name -like "values-zh*") {
    Copy-Item -LiteralPath $defaultStrings -Destination $strings -Force
  }

  Set-StringValue $strings "app_name_release" "KanjiIME"
  Set-StringValue $strings "app_name_debug" "KanjiIME"
  Set-StringValue $strings "trime_app_slogan" "English to Japanese and Chinese"
  Set-StringValue $strings "setup__enable_ime_hint" "Enable <b>KanjiIME</b> in Language and input settings" -RawXml
  Set-StringValue $strings "setup__select_ime_hint" "Select <b>KanjiIME</b> as your default input method" -RawXml
  Set-StringValue $strings "setup__enable_ime" "Enable KanjiIME"
  Set-StringValue $strings "setup__select_ime" "Select KanjiIME"
  Set-StringValue $strings "setup__next" "Next"
  Set-StringValue $strings "setup__prev" "Back"
  Set-StringValue $strings "setup__skip" "Skip"
  Set-StringValue $strings "setup__skip_hint" "Skip setup?"
  Set-StringValue $strings "setup__skip_hint_yes" "Yes"
  Set-StringValue $strings "setup__skip_hint_no" "No"
  Set-StringValue $strings "setup__step_one" "Step 1"
  Set-StringValue $strings "setup__step_two" "Step 2"
  Set-StringValue $strings "setup__step_three" "Step 3"
  Set-StringValue $strings "setup__request_permission_hint" "KanjiIME needs storage permission to deploy and update its local dictionaries."
  Set-StringValue $strings "setup__request_permission" "Request storage permission"
  Set-StringValue $strings "grant_permission" "Grant permission"
  Set-StringValue $strings "notification_permission_title" "Notification permission is disabled"
  Set-StringValue $strings "notification_permission_message" "KanjiIME cannot notify you when longer setup tasks finish."
  Set-StringValue $strings "setup_channel" "Setup"
  Set-StringValue $strings "setup__notify_hint" "Finish setting up KanjiIME"
  Set-StringValue $strings "done" "Done"
  Set-StringValue $strings "deploy" "Deploy"
  Set-StringValue $strings "deploy_progress" "Deploying..."
  Set-StringValue $strings "deploy_finish" "Deploy finished"
  Set-StringValue $strings "reset" "Reset"
  Set-StringValue $strings "reset_success" "Reset succeeded"
  Set-StringValue $strings "reset_failure" "Reset failed"
  Set-StringValue $strings "other_ime" "Other keyboards"
  Set-StringValue $strings "rime_daemon" "KanjiIME service"
  Set-StringValue $strings "restarting_rime" "Restarting KanjiIME"
  Set-StringValue $strings "external_storage_permission_granted" "Storage permission granted"
  Set-StringValue $strings "external_storage_permission_denied" "Storage permission denied. KanjiIME may not be able to deploy dictionaries."
  Set-StringValue $strings "external_storage_permission_not_available" "Storage permission is not available"
}

Write-Host "Patched Android branding strings under $res"
