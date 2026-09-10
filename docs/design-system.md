# Spotifin design system

Spotifin uses a Flutter-native design system based on the Spotify-inspired
reference in `.agents/skills/design/SKILL.md`.

## Foundations

- `lib/app/theme.dart` defines colors, radii, shadows, typography, and Material
  component themes.
- `lib/features/common/design_system.dart` defines spacing, breakpoints, and
  reusable product components.
- Manrope is bundled as an open-source alternative to Spotify's proprietary
  Circular-derived fonts; its OFL license is in `assets/fonts/OFL-Manrope.txt`.

## Rules

- Use `SpotifinColors` instead of literal interface colors.
- Use `SpotifinSpacing` and `SpotifinRadii` instead of new spacing or radius
  values where a token exists.
- Use green only for primary actions, playback, and selected states.
- Use `SpotifinSurface`, `SpotifinSettingsGroup`, `SpotifinCollectionCard`,
  `SpotifinEmptyState`, and `SpotifinPlayButton` before creating a local variant.
- Keep album artwork as the main source of color.
- Switch between bottom navigation and a sidebar at `SpotifinBreakpoints.rail`.
