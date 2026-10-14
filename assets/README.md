# Assets

- `font.ttf` — a subset of **Noto Sans** (Regular), used for all UI text.
  Licensed under the SIL Open Font License 1.1 (see `font.LICENSE.txt`).
  Subset to ASCII + Latin-1 + the em dash with `pyftsubset`.

The web build preloads this file (see `web/build_web.sh`); the desktop build
reads it from `assets/font.ttf` relative to the working directory. If it is
missing, the game falls back to raylib's built-in font.
