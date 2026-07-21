# Custom Theme Guide

## Fast path

1. Prepare one clean wallpaper. Use 16:9 when possible, keep the subject away from the area where you type, and do not include any Codex window, text, buttons, or screenshots.
2. Install this launcher, then run:

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "$env:LOCALAPPDATA\CodexThemeLauncher\engine\scripts\set-background.ps1" `
  -ImagePath "C:\path\to\wallpaper.jpg" `
  -Variant dark `
  -Accent "#c58ac8"
```

3. Reopen the generated `Codex` shortcut if Codex is not already running through the launcher.

The command copies the wallpaper into the active theme, updates `theme.json`, and reinjects the theme when a themed Codex session is already active.

## Create a named preset

Copy `assets/theme.json` beside your wallpaper and change these fields:

```json
{
  "id": "preset-my-theme",
  "name": "My Theme",
  "image": "my-wallpaper.jpg",
  "appearance": "dark",
  "palette": { "accent": "#c58ac8" },
  "art": {
    "focusX": 0.72,
    "focusY": 0.45,
    "safeArea": "left",
    "taskMode": "ambient"
  }
}
```

`focusX` and `focusY` select the image focus from `0` to `1`. `safeArea` is where text should remain readable: use `left`, `center`, `right`, or `none`. `taskMode` can be `ambient`, `banner`, or `off`.

## Prompt to paste into Codex

Attach your pure wallpaper and paste the following prompt into Codex. Replace the bracketed values before sending it.

```text
请把这张纯壁纸配置为 Codex Theme Launcher 的新预设。不要修改 WindowsApps、app.asar、Codex 登录信息或任何官方应用文件。

目标：
- 主题 ID：preset-[theme-id]
- 显示名称：[theme name]
- 外观：dark 或 light
- 强调色：[hex color]
- 壁纸焦点：focusX=[0-1]，focusY=[0-1]
- 可读文本安全区：left、center、right 或 none
- 任务页表现：ambient、banner 或 off

请仅执行以下工作：
1. 将我提供的纯壁纸复制到主题 assets 目录，并使用无歧义的英文文件名。
2. 更新 theme.json 中的 id、name、image、appearance、palette.accent 和 art 字段。
3. 保持现有的原生布局、输入框可点击性、宠物透明窗口兼容性、任务栏官方图标，以及缩略图自定义图标策略不变。
4. 不要把带 UI 的预览截图作为壁纸，不要修改无关文件。
5. 完成后运行现有注入器自检，并报告修改的文件和验证结果。
```

## Wallpaper prompt for an image model

```text
Create a clean 16:9 desktop wallpaper for a coding application: [visual style], [subject], [color palette]. Keep the left third calm and low-detail for readable navigation and text. Place the visual focus around [right/center] at roughly 45% height. No UI, no windows, no buttons, no text, no logos, no watermarks, and no character names. Use a polished illustration style with clear silhouettes and restrained contrast.
```
