[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$CodexExecutable,
  [Parameter(Mandatory = $true)][string]$IconPath,
  [int]$StartupTimeoutSeconds = 45,
  [int]$PollMilliseconds = 1500
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CodexExecutable -PathType Leaf)) {
  throw "Codex executable was not found: $CodexExecutable"
}
if (-not (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
  throw "Window icon was not found: $IconPath"
}
if ($StartupTimeoutSeconds -lt 1 -or $PollMilliseconds -lt 250) {
  throw 'StartupTimeoutSeconds must be positive and PollMilliseconds must be at least 250.'
}

if ('CodexThemeLauncher.WindowIconNative' -as [type]) {
  $native = [CodexThemeLauncher.WindowIconNative]
} else {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodexThemeLauncher {
  public static class WindowIconNative {
    private const uint WM_SETICON = 0x0080;
    private const int ICON_SMALL = 0;
    private const int ICON_BIG = 1;
    private const uint IMAGE_ICON = 1;
    private const uint LR_LOADFROMFILE = 0x0010;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadImage(
      IntPtr hinst,
      string lpszName,
      uint uType,
      int cxDesired,
      int cyDesired,
      uint fuLoad);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(
      IntPtr hWnd,
      uint message,
      IntPtr wParam,
      IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr icon);

    public static IntPtr LoadIcon(string path, int size) {
      return LoadImage(IntPtr.Zero, path, IMAGE_ICON, size, size, LR_LOADFROMFILE);
    }

    public static void Apply(IntPtr window, IntPtr largeIcon, IntPtr smallIcon) {
      SendMessage(window, WM_SETICON, new IntPtr(ICON_BIG), largeIcon);
      SendMessage(window, WM_SETICON, new IntPtr(ICON_SMALL), smallIcon);
    }
  }
}
'@
  $native = [CodexThemeLauncher.WindowIconNative]
}

$largeIcon = $native::LoadIcon($IconPath, 64)
$smallIcon = $native::LoadIcon($IconPath, 32)
if ($largeIcon -eq [IntPtr]::Zero -or $smallIcon -eq [IntPtr]::Zero) {
  if ($largeIcon -ne [IntPtr]::Zero) { [void]$native::DestroyIcon($largeIcon) }
  if ($smallIcon -ne [IntPtr]::Zero) { [void]$native::DestroyIcon($smallIcon) }
  throw "Windows could not load the icon: $IconPath"
}

function Get-CodexWindowHandles {
  param([Parameter(Mandatory = $true)][string]$Executable)

  $handles = @()
  foreach ($process in @(Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue)) {
    try {
      if ($process.Path -and $process.Path -ieq $Executable -and $process.MainWindowHandle -ne 0) {
        $handles += [IntPtr]$process.MainWindowHandle
      }
    } catch {}
  }
  return @($handles | Select-Object -Unique)
}

$deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
$attached = $false
$announcedHandles = @{}
try {
  while ($true) {
    $handles = @(Get-CodexWindowHandles -Executable $CodexExecutable)
    if ($handles.Count -gt 0) {
      $attached = $true
      foreach ($handle in $handles) {
        $native::Apply($handle, $largeIcon, $smallIcon)
        $handleKey = $handle.ToInt64().ToString()
        if (-not $announcedHandles.ContainsKey($handleKey)) {
          $announcedHandles[$handleKey] = $true
          Write-Output "Applied the custom Codex icon to window 0x$($handle.ToInt64().ToString('X'))."
        }
      }
    } elseif ($attached -or (Get-Date) -ge $deadline) {
      break
    }
    Start-Sleep -Milliseconds $PollMilliseconds
  }
} finally {
  [void]$native::DestroyIcon($largeIcon)
  [void]$native::DestroyIcon($smallIcon)
}
