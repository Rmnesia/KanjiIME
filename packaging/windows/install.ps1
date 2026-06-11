$ErrorActionPreference = "Stop"

$log = Join-Path $env:TEMP "KanjiIME-Setup.log"
Start-Transcript -Path $log -Force | Out-Null

function Write-Step([string]$Message) {
  Write-Host ""
  Write-Host $Message
}

function Find-WeaselDeployer {
  $roots = @(
    (Join-Path ${env:ProgramFiles(x86)} "Rime"),
    (Join-Path $env:ProgramFiles "Rime")
  ) | Where-Object { $_ -and (Test-Path $_) }

  foreach ($root in $roots) {
    $match = Get-ChildItem -LiteralPath $root -Recurse -Filter "WeaselDeployer.exe" -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($match) {
      return $match.FullName
    }
  }

  return $null
}

try {
  $payloadDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $rimeDir = Join-Path $env:APPDATA "Rime"
  $installer = Join-Path $payloadDir "weasel-installer.exe"

  Write-Host "KanjiIME Windows Setup"
  Write-Host "Log: $log"

  $deployer = Find-WeaselDeployer
  if (!$deployer) {
    if (!(Test-Path $installer)) {
      throw "Bundled Weasel installer was not found: $installer"
    }

    Write-Step "Installing Rime Weasel silently..."
    $process = Start-Process -FilePath $installer -ArgumentList "/S" -Wait -PassThru
    if ($process.ExitCode -ne 0) {
      throw "Weasel installer failed with exit code $($process.ExitCode)."
    }

    Start-Sleep -Seconds 2
    $deployer = Find-WeaselDeployer
  }

  Write-Step "Installing KanjiIME dictionaries..."
  New-Item -ItemType Directory -Force -Path $rimeDir | Out-Null
  Get-ChildItem -LiteralPath $payloadDir -Filter "*.yaml" | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $rimeDir -Force
  }

  if (!$deployer) {
    throw "WeaselDeployer.exe was not found after installation."
  }

  Write-Step "Deploying KanjiIME..."
  $deploy = Start-Process -FilePath $deployer -ArgumentList "/deploy" -Wait -PassThru
  if ($deploy.ExitCode -ne 0) {
    throw "Weasel deployment failed with exit code $($deploy.ExitCode)."
  }

  Write-Step "KanjiIME is ready."
  Write-Host "Default mode: KanjiIME JP"
  Write-Host "Other modes: KanjiIME ZH, KanjiIME HK"
  Write-Host "Installed Rime data to: $rimeDir"
  exit 0
} catch {
  Write-Host ""
  Write-Host "KanjiIME setup failed:"
  Write-Host $_.Exception.Message
  Write-Host ""
  Write-Host "Log: $log"
  exit 1
} finally {
  Stop-Transcript | Out-Null
}
