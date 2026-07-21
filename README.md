# Ritual Ink Bloom for Codex

An unofficial Windows theme launcher for the Microsoft Store Codex desktop app. It starts the official app with a loopback-only Chromium DevTools Protocol (CDP) port and injects a reversible CSS/JS theme into its renderer. It does not modify `WindowsApps`, `app.asar`, application signatures, user authentication, tasks, plugins, or Codex settings.

`Ritual Ink Bloom` is the bundled sample preset: a generated ink-and-petal illustration, a matching desktop/thumbnail icon, and a CSS-only falling-petal layer. The title is a maintainer-defined theme name and does not identify or claim to represent any character or official artwork.

## What It Does

- Keeps Codex controls real and interactive: sidebar, task pages, project picker, composer, and menus remain native UI.
- Uses a single generated wallpaper as a low-opacity task-page atmosphere layer.
- Uses 26 CSS petals animated only through `transform` and `opacity`; they are behind app content, have no canvas, and do not receive pointer events.
- Keeps the desktop shortcut and taskbar thumbnail on the bundled icon, while the fixed taskbar button retains the official Codex package icon.
- Runs the Node injector and icon helper hidden. No terminal, tray icon, or extra window is created.
- Supports custom wallpapers and theme metadata. See [the custom theme guide](docs/CUSTOM_THEME_GUIDE.md).

## Requirements

- Official Microsoft Store `OpenAI.Codex` app registered for the current Windows user.
- Node.js 22 or newer available on `PATH`.
- Windows PowerShell 5.1 or newer.

## Install

Run from this repository root:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\install.ps1 -ShortcutName Codex
```

The installer copies the engine to `%LOCALAPPDATA%\CodexThemeLauncher\engine`, prepares `%LOCALAPPDATA%\CodexThemeLauncher\active-theme`, and creates hidden-launch shortcuts. Start the generated `Codex` shortcut for the themed app. If an unthemed Codex process is already open, this shortcut restarts it so CDP can be enabled; unsaved composer text can be lost.

## Custom Themes

The quickest path is to supply a clean wallpaper and let the included script update the active theme:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "$env:LOCALAPPDATA\CodexThemeLauncher\engine\scripts\set-background.ps1" `
  -ImagePath "C:\path\to\your-wallpaper.jpg" `
  -Variant dark `
  -Accent "#c58ac8"
```

Use a pure wallpaper, not a screenshot containing Codex UI. Supported formats are `.svg`, `.jpg`, `.jpeg`, `.png`, `.webp`, and `.gif`; the file must be 16 MB or smaller. For a named preset, focus point, safe area, and a ready-to-paste Codex prompt, follow [docs/CUSTOM_THEME_GUIDE.md](docs/CUSTOM_THEME_GUIDE.md).

## Restore

Close Codex, then run:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "$env:LOCALAPPDATA\CodexThemeLauncher\engine\scripts\restore-codex-skin.ps1"
```

## Safety

- CDP is bound only to `127.0.0.1`, but it has no same-user authentication. Do not run untrusted local software while the themed session is active.
- This is not an OpenAI product and is not affiliated with or endorsed by OpenAI.
- Codex and OpenAI names, marks, and application assets belong to their respective owners.

## Attribution and Artwork

This repository contains modified work based on the Windows renderer/theme implementation from [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin). The included MIT license and [NOTICE.md](NOTICE.md) describe the attribution, license terms, and the separate status of the bundled demonstration artwork.
