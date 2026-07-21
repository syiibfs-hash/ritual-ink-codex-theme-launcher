[CmdletBinding()]
param(
  [string]$ShortcutName = 'Codex Skin',
  [string]$IconPath,
  [switch]$NoDesktopShortcut,
  [switch]$NoStartMenuShortcut
)

$ErrorActionPreference = 'Stop'

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = [System.IO.Path]::GetFullPath($sourceRoot)
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexThemeLauncher'
$engineRoot = Join-Path $stateRoot 'engine'

if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'scripts\common.ps1') -PathType Leaf)) {
  throw 'Install must be run from the CodexThemeLauncher package root.'
}

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null

if (Test-Path -LiteralPath $engineRoot) {
  $fullEngine = [System.IO.Path]::GetFullPath($engineRoot)
  $fullState = [System.IO.Path]::GetFullPath($stateRoot).TrimEnd('\') + '\'
  if (-not $fullEngine.StartsWith($fullState, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace unexpected engine path: $fullEngine"
  }
  Remove-Item -LiteralPath $engineRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $engineRoot | Out-Null
foreach ($name in @('assets', 'scripts', 'bin')) {
  Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination $engineRoot -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'README.md') -Destination $engineRoot -Force -ErrorAction SilentlyContinue

. (Join-Path $engineRoot 'scripts\common.ps1')
$paths = Get-CtlPaths
Initialize-CtlThemeStore -Paths $paths
$node = Get-CtlNodeRuntime
$codex = Get-CtlCodexInstall

if (-not $IconPath) {
  $bundledIcon = Join-Path $paths.Assets 'ritual-ink-bloom.ico'
  $IconPath = if (Test-Path -LiteralPath $bundledIcon -PathType Leaf) { $bundledIcon } else { $codex.Executable }
}

$startScript = Join-Path $paths.Scripts 'start-codex-skin.ps1'
$restoreScript = Join-Path $paths.Scripts 'restore-codex-skin.ps1'

if (-not $NoDesktopShortcut) {
  $desktop = [Environment]::GetFolderPath('Desktop')
  New-CtlShortcut `
    -ShortcutPath (Join-Path $desktop "$ShortcutName.lnk") `
    -ScriptPath $startScript `
    -ScriptArguments @('-RestartExisting') `
    -IconPath $IconPath `
    -WorkingDirectory $paths.EngineRoot
}

if (-not $NoStartMenuShortcut) {
  $programs = [Environment]::GetFolderPath('Programs')
  $folder = Join-Path $programs 'Codex Theme Launcher'
  New-CtlShortcut `
    -ShortcutPath (Join-Path $folder "$ShortcutName.lnk") `
    -ScriptPath $startScript `
    -ScriptArguments @('-RestartExisting') `
    -IconPath $IconPath `
    -WorkingDirectory $paths.EngineRoot
  New-CtlShortcut `
    -ShortcutPath (Join-Path $folder 'Restore Codex Skin.lnk') `
    -ScriptPath $restoreScript `
    -IconPath $IconPath `
    -WorkingDirectory $paths.EngineRoot
}

Write-Host "Installed to $engineRoot"
Write-Host "Node.js $($node.Version) is available at $($node.Path)"
Write-Host "Codex package: $($codex.PackageFullName)"
