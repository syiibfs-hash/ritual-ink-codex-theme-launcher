[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$RestartExisting,
  [switch]$ForegroundInjector
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-CtlPort -Port $Port
$paths = Get-CtlPaths
New-Item -ItemType Directory -Force -Path $paths.StateRoot | Out-Null
Initialize-CtlThemeStore -Paths $paths

$node = Get-CtlNodeRuntime
$codex = Get-CtlCodexInstall
$injector = Join-Path $paths.Scripts 'injector.mjs'
$iconSyncScript = Join-Path $paths.Scripts 'sync-window-icon.ps1'
$iconPath = Join-Path $paths.Assets 'ritual-ink-bloom.ico'
$previousState = Read-CtlJson -Path $paths.StateFile
Stop-CtlRecordedInjector -State $previousState
Stop-CtlRecordedIconSync -State $previousState

if (-not (Test-Path -LiteralPath $iconSyncScript -PathType Leaf)) {
  throw "Window icon synchronizer was not found: $iconSyncScript"
}
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
  throw "Window icon was not found: $iconPath"
}

$cdpReady = Test-CtlCdpReady -Port $Port
if (-not $cdpReady -and -not (Test-CtlPortAvailable -Port $Port)) {
  $Port = Select-CtlPort -PreferredPort $Port
}

$codexProcesses = @(Get-CtlCodexProcesses -Codex $codex)
if (-not $cdpReady -and $codexProcesses.Count -gt 0) {
  if (-not $RestartExisting) {
    throw 'Codex is already open without this skin launcher. Close Codex first or run with -RestartExisting.'
  }
  Stop-CtlCodexProcesses -Codex $codex
}

if (-not (Test-CtlCdpReady -Port $Port)) {
  [void](Start-CtlCodex -Codex $codex -Arguments @(
    '--remote-debugging-address=127.0.0.1',
    "--remote-debugging-port=$Port"
  ))
}

$deadline = (Get-Date).AddSeconds(45)
while (-not (Test-CtlCdpReady -Port $Port)) {
  if ((Get-Date) -ge $deadline) {
    throw "Codex did not expose a loopback CDP endpoint on port $Port within 45 seconds."
  }
  Start-Sleep -Milliseconds 400
}

$browserId = Get-CtlBrowserId -Port $Port
if (-not $browserId) { throw 'The Codex CDP browser identity could not be read.' }

if ($ForegroundInjector) {
  & $node.Path $injector --watch --port $Port --theme-dir $paths.ActiveTheme
  exit $LASTEXITCODE
}

$daemon = Start-Process -FilePath $node.Path -ArgumentList @(
  $injector,
  '--watch',
  '--port',
  "$Port",
  '--theme-dir',
  $paths.ActiveTheme
) -WindowStyle Hidden -PassThru -RedirectStandardOutput $paths.InjectorLog -RedirectStandardError $paths.InjectorErrorLog

Start-Sleep -Milliseconds 700
if ($daemon.HasExited) {
  throw "The injector exited during startup. See $($paths.InjectorErrorLog)"
}

& $node.Path $injector --verify --port $Port --theme-dir $paths.ActiveTheme --timeout-ms 30000
if ($LASTEXITCODE -ne 0) {
  try { Stop-Process -Id $daemon.Id -Force -ErrorAction SilentlyContinue } catch {}
  Remove-Item -LiteralPath $paths.StateFile -Force -ErrorAction SilentlyContinue
  throw "Skin verification failed. See $($paths.InjectorErrorLog)"
}

$iconSyncArguments = ConvertTo-CtlArgumentLine -Arguments @(
  '-NoProfile',
  '-ExecutionPolicy', 'RemoteSigned',
  '-File', $iconSyncScript,
  '-CodexExecutable', $codex.Executable,
  '-IconPath', $iconPath
)
$iconSync = Start-Process -FilePath 'powershell.exe' -ArgumentList $iconSyncArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $paths.IconSyncLog -RedirectStandardError $paths.IconSyncErrorLog

Start-Sleep -Milliseconds 500
if ($iconSync.HasExited) {
  throw "The window icon synchronizer exited during startup. See $($paths.IconSyncErrorLog)"
}

$state = [pscustomobject]@{
  schemaVersion = 2
  platform = 'windows'
  port = $Port
  injectorPid = $daemon.Id
  iconSyncPid = $iconSync.Id
  browserId = $browserId
  nodePath = $node.Path
  nodeVersion = $node.Version
  codexExe = $codex.Executable
  codexPackageRoot = $codex.PackageRoot
  codexPackageFullName = $codex.PackageFullName
  codexPackageFamilyName = $codex.PackageFamilyName
  themeDir = $paths.ActiveTheme
  createdAt = (Get-Date).ToUniversalTime().ToString('o')
}
Write-CtlUtf8Json -Path $paths.StateFile -Value $state
Write-Host "Codex skin is active on loopback port $Port."
