[CmdletBinding()]
param(
  [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$paths = Get-CtlPaths
$node = Get-CtlNodeRuntime
$codex = Get-CtlCodexInstall
$injector = Join-Path $paths.Scripts 'injector.mjs'
$state = Read-CtlJson -Path $paths.StateFile

if ($null -ne $state -and $state.port) {
  try {
    & $node.Path $injector --remove --port ([int]$state.port) --theme-dir $paths.ActiveTheme --timeout-ms 8000
  } catch {}
}

Stop-CtlRecordedInjector -State $state
Stop-CtlRecordedIconSync -State $state
Remove-Item -LiteralPath $paths.StateFile -Force -ErrorAction SilentlyContinue

if (-not $NoRestart) {
  Stop-CtlCodexProcesses -Codex $codex
  [void](Start-CtlCodex -Codex $codex)
}

Write-Host 'Codex skin has been removed.'
