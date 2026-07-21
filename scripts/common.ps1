Set-StrictMode -Version Latest

function Get-CtlStateRoot {
  return (Join-Path $env:LOCALAPPDATA 'CodexThemeLauncher')
}

function Get-CtlEngineRoot {
  return (Split-Path -Parent $PSScriptRoot)
}

function Get-CtlPaths {
  $stateRoot = Get-CtlStateRoot
  $engineRoot = Get-CtlEngineRoot
  return [pscustomobject]@{
    StateRoot = $stateRoot
    EngineRoot = $engineRoot
    Scripts = Join-Path $engineRoot 'scripts'
    Assets = Join-Path $engineRoot 'assets'
    Bin = Join-Path $engineRoot 'bin'
    ActiveTheme = Join-Path $stateRoot 'active-theme'
    StateFile = Join-Path $stateRoot 'state.json'
    InjectorLog = Join-Path $stateRoot 'injector.log'
    InjectorErrorLog = Join-Path $stateRoot 'injector-error.log'
    IconSyncLog = Join-Path $stateRoot 'icon-sync.log'
    IconSyncErrorLog = Join-Path $stateRoot 'icon-sync-error.log'
  }
}

function Assert-CtlPort {
  param([Parameter(Mandatory = $true)][int]$Port)
  if ($Port -lt 1024 -or $Port -gt 65535) {
    throw "Port must be between 1024 and 65535: $Port"
  }
}

function Test-CtlPathEqual {
  param([string]$Left, [string]$Right)
  if (-not $Left -or -not $Right) { return $false }
  try {
    return ([System.IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Right).TrimEnd('\'))
  } catch {
    return $false
  }
}

function Test-CtlPathWithin {
  param([string]$Path, [string]$Root)
  if (-not $Path -or -not $Root) { return $false }
  try {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Write-CtlUtf8Json {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $directory = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $json = $Value | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($Path, $json + "`r`n", [System.Text.UTF8Encoding]::new($false))
}

function Read-CtlJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
}

function Get-CtlNodeRuntime {
  param([int]$MinimumMajor = 22)
  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command node -ErrorAction SilentlyContinue }
  if (-not $command) { throw "Node.js $MinimumMajor or newer is required and was not found in PATH." }
  $version = (& $command.Source -p "process.versions.node").Trim()
  if (-not $version) { throw 'Node.js version could not be detected.' }
  $major = 0
  if (-not [int]::TryParse(($version -split '\.')[0], [ref]$major) -or $major -lt $MinimumMajor) {
    throw "Node.js $MinimumMajor or newer is required; found $version at $($command.Source)."
  }
  return [pscustomobject]@{ Path = $command.Source; Version = $version; Major = $major }
}

function ConvertTo-CtlArgumentLine {
  param([AllowEmptyCollection()][string[]]$Arguments = @())
  $escaped = foreach ($argument in $Arguments) {
    if ($argument -match '[\s"]') {
      '"' + ($argument -replace '"', '\"') + '"'
    } else {
      $argument
    }
  }
  return ($escaped -join ' ')
}

function Initialize-CtlPackageLauncher {
  if ('CodexThemeLauncher.PackageLauncher' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodexThemeLauncher {
  [Flags]
  internal enum ActivateOptions : uint {
    None = 0
  }

  [ComImport]
  [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
  [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  internal interface IApplicationActivationManager {
    [PreserveSig]
    int ActivateApplication(
      [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
      [MarshalAs(UnmanagedType.LPWStr)] string arguments,
      ActivateOptions options,
      out uint processId);
  }

  [ComImport]
  [Guid("45ba127d-10a8-46ea-8ab7-56ea9078943c")]
  internal class ApplicationActivationManager {}

  public static class PackageLauncher {
    public static uint Launch(string appUserModelId, string arguments) {
      var manager = (IApplicationActivationManager)new ApplicationActivationManager();
      try {
        uint processId;
        int result = manager.ActivateApplication(
          appUserModelId,
          arguments ?? string.Empty,
          ActivateOptions.None,
          out processId);
        Marshal.ThrowExceptionForHR(result);
        return processId;
      } finally {
        if (Marshal.IsComObject(manager)) Marshal.FinalReleaseComObject(manager);
      }
    }
  }
}
'@
}

function ConvertTo-CtlCodexInstall {
  param([Parameter(Mandatory = $true)][object]$Package)
  if ("$($Package.Name)" -ine 'OpenAI.Codex' -or -not $Package.InstallLocation) { return $null }
  $packageRoot = "$($Package.InstallLocation)"
  $executable = Join-Path $packageRoot 'app\ChatGPT.exe'
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { return $null }
  try {
    $manifest = Get-AppxPackageManifest -Package $Package -ErrorAction Stop
    $apps = @($manifest.Package.Applications.Application | Where-Object {
      "$($_.Executable)".Replace('/', '\') -ieq 'app\ChatGPT.exe'
    })
    if ($apps.Count -ne 1) { return $null }
    $applicationId = "$($apps[0].Id)"
  } catch {
    return $null
  }
  $packageFamilyName = "$($Package.PackageFamilyName)"
  if ($packageFamilyName -cnotmatch '^[A-Za-z0-9._-]{1,128}$' -or $applicationId -cnotmatch '^[A-Za-z0-9._-]{1,64}$') {
    return $null
  }
  return [pscustomobject]@{
    PackageRoot = $packageRoot
    Executable = $executable
    Version = "$($Package.Version)"
    PackageFullName = "$($Package.PackageFullName)"
    PackageFamilyName = $packageFamilyName
    ApplicationId = $applicationId
    AppUserModelId = "$packageFamilyName!$applicationId"
  }
}

function Get-CtlCodexInstall {
  $packages = @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop | Sort-Object Version -Descending)
  foreach ($package in $packages) {
    $install = ConvertTo-CtlCodexInstall -Package $package
    if ($null -ne $install) { return $install }
  }
  throw 'The official OpenAI.Codex Store package was not found or could not be validated.'
}

function Start-CtlCodex {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [AllowEmptyCollection()][string[]]$Arguments = @()
  )
  Initialize-CtlPackageLauncher
  $argumentLine = ConvertTo-CtlArgumentLine -Arguments $Arguments
  $processId = [CodexThemeLauncher.PackageLauncher]::Launch("$($Codex.AppUserModelId)", $argumentLine)
  if ($processId -le 0) { throw 'Windows did not return a Codex process ID after package activation.' }
  return $processId
}

function Get-CtlCodexProcesses {
  param([Parameter(Mandatory = $true)][object]$Codex)
  $result = @()
  foreach ($process in Get-Process -ErrorAction SilentlyContinue) {
    try {
      if ($process.Path -and (Test-CtlPathEqual -Left $process.Path -Right $Codex.Executable)) {
        $result += $process
      }
    } catch {}
  }
  return $result
}

function Stop-CtlCodexProcesses {
  param([Parameter(Mandatory = $true)][object]$Codex)
  $processes = @(Get-CtlCodexProcesses -Codex $Codex)
  foreach ($process in $processes) {
    try {
      if ($process.MainWindowHandle -and -not $process.HasExited) {
        [void]$process.CloseMainWindow()
      }
    } catch {}
  }
  $deadline = (Get-Date).AddSeconds(6)
  do {
    Start-Sleep -Milliseconds 250
    $remaining = @(Get-CtlCodexProcesses -Codex $Codex)
  } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)
  foreach ($process in @(Get-CtlCodexProcesses -Codex $Codex)) {
    try { Stop-Process -Id $process.Id -Force -ErrorAction Stop } catch {}
  }
}

function Test-CtlPortAvailable {
  param([Parameter(Mandatory = $true)][int]$Port)
  try {
    $listener = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return $null -eq $listener
  } catch {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
      $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
      $connected = $async.AsyncWaitHandle.WaitOne(300)
      if ($connected) {
        $client.EndConnect($async)
        return $false
      }
      return $true
    } catch {
      return $true
    } finally {
      $client.Close()
    }
  }
}

function Select-CtlPort {
  param([Parameter(Mandatory = $true)][int]$PreferredPort)
  for ($candidate = $PreferredPort; $candidate -le [Math]::Min(65535, $PreferredPort + 100); $candidate++) {
    if (Test-CtlPortAvailable -Port $candidate) { return $candidate }
  }
  throw "No free loopback port was found between $PreferredPort and $([Math]::Min(65535, $PreferredPort + 100))."
}

function Get-CtlCdpVersion {
  param([Parameter(Mandatory = $true)][int]$Port)
  try {
    return Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 -MaximumRedirection 0 -ErrorAction Stop
  } catch {
    return $null
  }
}

function Get-CtlCdpTargets {
  param([Parameter(Mandatory = $true)][int]$Port)
  try {
    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2 -MaximumRedirection 0 -ErrorAction Stop
    return @($targets | Where-Object { "$($_.type)" -ceq 'page' -and "$($_.url)" -like 'app://*' })
  } catch {
    return @()
  }
}

function Get-CtlBrowserId {
  param([Parameter(Mandatory = $true)][int]$Port)
  $version = Get-CtlCdpVersion -Port $Port
  if ($null -eq $version -or -not $version.webSocketDebuggerUrl) { return $null }
  $match = [regex]::Match("$($version.webSocketDebuggerUrl)", '/devtools/browser/(?<id>[A-Za-z0-9._-]{1,200})$')
  if (-not $match.Success) { return $null }
  return $match.Groups['id'].Value
}

function Test-CtlCdpReady {
  param([Parameter(Mandatory = $true)][int]$Port)
  return [bool]((Get-CtlBrowserId -Port $Port) -and @(Get-CtlCdpTargets -Port $Port).Count -gt 0)
}

function Initialize-CtlThemeStore {
  param(
    [Parameter(Mandatory = $true)][object]$Paths
  )
  New-Item -ItemType Directory -Force -Path $Paths.ActiveTheme | Out-Null
  $themePath = Join-Path $Paths.ActiveTheme 'theme.json'
  if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
    Copy-Item -LiteralPath (Join-Path $Paths.Assets 'theme.json') -Destination $themePath -Force
  }
  $theme = Read-CtlJson -Path $themePath
  $imageName = $null
  if ($null -ne $theme) {
    $themeProperties = @($theme.PSObject.Properties.Name)
    if ($themeProperties -contains 'image' -and "$($theme.image)".Trim()) {
      $imageName = "$($theme.image)".Trim()
    }
  }
  if (-not $imageName) {
    Copy-Item -LiteralPath (Join-Path $Paths.Assets 'theme.json') -Destination $themePath -Force
    $theme = Read-CtlJson -Path $themePath
    $themeProperties = @($theme.PSObject.Properties.Name)
    if ($themeProperties -notcontains 'image' -or -not "$($theme.image)".Trim()) {
      throw 'Bundled theme.json is missing its image field.'
    }
    $imageName = "$($theme.image)".Trim()
  }
  $wallpaperPath = Join-Path $Paths.ActiveTheme $imageName
  if (-not (Test-Path -LiteralPath $wallpaperPath -PathType Leaf)) {
    $assetWallpaper = Join-Path $Paths.Assets $imageName
    if (-not (Test-Path -LiteralPath $assetWallpaper -PathType Leaf)) {
      throw "Theme image is missing from package assets: $imageName"
    }
    Copy-Item -LiteralPath $assetWallpaper -Destination $wallpaperPath -Force
  }
}

function Stop-CtlRecordedInjector {
  param([AllowNull()][object]$State)
  if ($null -eq $State -or -not $State.injectorPid) { return }
  $pidValue = 0
  if (-not [int]::TryParse("$($State.injectorPid)", [ref]$pidValue) -or $pidValue -le 0) { return }
  try {
    $process = Get-Process -Id $pidValue -ErrorAction Stop
    Stop-Process -Id $process.Id -Force -ErrorAction Stop
  } catch {}
}

function Stop-CtlRecordedIconSync {
  param([AllowNull()][object]$State)
  if ($null -eq $State) { return }
  $pidProperty = $State.PSObject.Properties['iconSyncPid']
  if ($null -eq $pidProperty -or -not $pidProperty.Value) { return }
  $pidValue = 0
  if (-not [int]::TryParse("$($pidProperty.Value)", [ref]$pidValue) -or $pidValue -le 0) { return }
  try {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$pidValue" -ErrorAction Stop
    if ("$($process.Name)" -notmatch '^powershell(?:_ise)?\.exe$') { return }
    if ("$($process.CommandLine)" -notlike '*sync-window-icon.ps1*') { return }
    Stop-Process -Id $pidValue -Force -ErrorAction Stop
  } catch {}
}

function New-CtlShortcut {
  param(
    [Parameter(Mandatory = $true)][string]$ShortcutPath,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [string[]]$ScriptArguments = @(),
    [string]$IconPath,
    [string]$WorkingDirectory
  )
  $directory = Split-Path -Parent ([System.IO.Path]::GetFullPath($ShortcutPath))
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $paths = Get-CtlPaths
  $runner = Join-Path $paths.Bin 'run-hidden.vbs'
  $wsh = New-Object -ComObject WScript.Shell
  $shortcut = $wsh.CreateShortcut($ShortcutPath)
  $shortcut.TargetPath = (Join-Path $env:WINDIR 'System32\wscript.exe')
  $quoted = @("`"$runner`"", "`"$ScriptPath`"") + $ScriptArguments
  $shortcut.Arguments = ($quoted -join ' ')
  $shortcut.WorkingDirectory = if ($WorkingDirectory) { $WorkingDirectory } else { $paths.EngineRoot }
  if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
    $shortcut.IconLocation = "$IconPath,0"
  }
  $shortcut.WindowStyle = 7
  $shortcut.Save()
}
