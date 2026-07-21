# Notices

## Upstream attribution

This repository includes modified theme assets and renderer code based on the Windows implementation in `Fei-Away/Codex-Dream-Skin`:

- Upstream repository: https://github.com/Fei-Away/Codex-Dream-Skin
- Upstream copyright: Copyright (c) 2026 Codex Dream Skin Studio contributors
- Upstream license: MIT, reproduced in [LICENSE](LICENSE)

The following local files are modified derivatives of that implementation: `assets/dream-skin.css`, `assets/renderer-inject.js`, and `assets/theme.json`. This project also uses the same external, loopback-only CDP theme-injection approach.

## Artwork and marks

`Ritual Ink Bloom` is a maintainer-defined label for the bundled generated demonstration preset. It does not identify, depict by name, or claim endorsement by any character, franchise, artist, or rights holder. The bundled wallpaper and icon are example assets and are excluded from the MIT software license. Anyone reusing or redistributing them is responsible for an independent review of applicable model-output, artwork, trademark, and other rights.

This project is unofficial and is not affiliated with, endorsed by, or sponsored by OpenAI. The OpenAI and Codex names, logos, product appearance, and application binaries are not licensed by this repository.

## Runtime security

Themes use Chromium DevTools Protocol on `127.0.0.1`. A same-user process can attach to that debugging endpoint while Codex is running. Treat the active session as sensitive and close Codex or run the restore script when finished.
