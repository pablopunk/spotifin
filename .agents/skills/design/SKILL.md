# Spotifin Design System

## 1. Brand Direction

Spotifin is a dark, immersive music player with an identity drawn from light moving across a mirrored disco ball. The interface stays quiet and near-black so album artwork remains prominent, while solid Aurora Cyan marks actions and active states.

The visual character is nocturnal, luminous, compact, and tactile. Reserve the multicolor gradient for the logo and use solid colors throughout the interface.

**Key characteristics:**
- Near-black layered surfaces (`#0B0D12` to `#242731`)
- Aurora Cyan for controls, focus, progress, and active states
- Manrope typography with a compact bold/regular hierarchy
- Pill buttons and circular playback controls
- Dense layouts optimized for scanning music collections
- Album artwork remains the main source of content color

## 2. Color Palette

### Brand
- **Aurora Cyan** (`#39F4D1`): Primary accent, CTA, focus, progress, and active state
- **Electric Blue** (`#33BFFF`): Logo gradient midpoint
- **Pulse Violet** (`#9B68FF`): Logo gradient end
- **Aurora gradient**: `linear-gradient(90deg, #39F4D1 0%, #33BFFF 52%, #9B68FF 100%)`

### Surfaces
- **Void** (`#0B0D12`): Deepest application background
- **Background** (`#111319`): Main content background
- **Surface** (`#181B22`): Sidebar, cards, and panels
- **Interactive** (`#20232C`): Inputs and controls
- **Raised** (`#292D38`): Menus and elevated cards
- **Hover** (`#303541`): Hover and pressed surfaces
- **Border** (`#454B59`): Quiet separators
- **Strong border** (`#71798A`): Focused outlines

### Text
- **Primary** (`#FFFFFF`): Titles and important content
- **Secondary** (`#B8BECA`): Metadata and inactive navigation
- **Disabled** (`#737A89`): Unavailable controls

### Semantic
- **Negative** (`#F3727F`): Errors and destructive actions
- **Warning** (`#FFA42B`): Warnings
- **Information** (`#539DF5`): Neutral notices

## 3. Gradient Rules

### Use the aurora gradient for
- The logo and wordmark only

### Do not use the aurora gradient for
- Buttons, playback controls, navigation, progress, or focus
- Body text, metadata, surfaces, cards, or dividers
- Error, warning, favorite, or download status
- Album-art overlays

Use Aurora Cyan for all primary actions and active states. Controls placed over cyan use `#0B0D12` for strong contrast.

## 4. Typography

Use **Manrope** for all interface and title text with platform sans-serif fallbacks.

| Role | Size | Weight | Notes |
|------|------|--------|-------|
| Page or section title | 24px | 700 | Highest page-level emphasis |
| Feature heading | 18px | 700 | Card and panel headings |
| Body strong | 16px | 700 | Important content |
| Body | 16px | 400 | Standard copy |
| Navigation | 14px | 400/700 | Bold only when active |
| Button | 14px | 700 | Compact, direct labels |
| Metadata | 12px–14px | 400 | Secondary color |
| Badge | 10px–12px | 600–700 | Short labels only |

Keep line heights compact. Create hierarchy with weight and contrast before increasing size.

## 5. Components

### Primary playback control
- Solid Aurora Cyan background
- Near-black icon
- Circular shape
- 48px standard size, 64px featured size
- Subtle dark shadow for separation

### Primary action
- Solid Aurora Cyan background
- Near-black text or icon
- Full pill shape
- Use only for the main action in a region

### Secondary action
- `#20232C` background or transparent
- White text
- Strong-border outline when needed
- Full pill shape

### Selected navigation
- Solid Aurora Cyan background
- Near-black icon and label
- Full pill shape
- Inactive items use transparent backgrounds and secondary text

### Search input
- `#20232C` background
- White input text and secondary placeholder
- Full pill shape
- Quiet border at rest and Aurora Cyan focus ring

### Cards
- `#181B22` or `#20232C` background
- 8px radius
- No visible border by default
- Raise to `#292D38` with a dark shadow on hover

### Dialogs and menus
- `#292D38` surface
- 12px radius
- Heavy dark shadow
- Keep the content compact and left aligned

## 6. Layout

### Spacing
Use an 8px base rhythm with practical steps of 4, 8, 12, 16, 20, 24, and 32px.

### Density
- Prefer content density over decorative whitespace
- Keep track rows easy to scan
- Use dark negative space to separate sections
- Keep the playback bar visible in detail views

### Radius
- 4px: Small artwork and compact elements
- 8px: Cards
- 12px: Panels and dialogs
- 999px: Pills
- Circle: Playback and icon-only controls

## 7. Depth

| Level | Treatment | Use |
|------|-----------|-----|
| Base | `#111319` | Main background |
| Surface | `#181B22` | Sidebar and cards |
| Interactive | `#20232C` | Inputs and controls |
| Raised | `#292D38` plus dark shadow | Menus and hover cards |
| Dialog | `rgba(0,0,0,0.55) 0 8px 24px` | Dialogs and overlays |

Shadows must be strong enough to remain visible on dark surfaces, but gradient glow must not replace functional focus indicators.

## 8. Responsive Behavior

| Range | Behavior |
|------|----------|
| Under 576px | Mobile navigation and bottom sheets |
| 576–895px | Adaptive grids and compact controls |
| 896–1149px | Collapsed desktop sidebar |
| 1150–1399px | Extended sidebar |
| 1400px and above | Optional persistent right panels |

Keep search available at every size, preserve playback access, and reduce columns before shrinking artwork below a useful size.

## 9. Do and Do Not

### Do
- Keep the application shell dark and visually quiet
- Keep the aurora gradient exclusive to the logo
- Use Aurora Cyan for CTAs, active controls, focus, and progress
- Preserve strong contrast and visible keyboard focus
- Let album artwork supply most view-specific color
- Keep controls tactile with pill and circular geometry

### Do not
- Use gradients outside the logo
- Introduce unrelated decorative colors
- Use Aurora Cyan for semantic statuses
- Reduce contrast to create a glow effect
- Add spacious marketing-page layouts to dense application views

## 10. Implementation Reference

```dart
const auroraGradient = LinearGradient(
  colors: [Color(0xFF39F4D1), Color(0xFF33BFFF), Color(0xFF9B68FF)],
);
```

Start each design with the dark surface hierarchy, add album artwork, use Aurora Cyan for interactive emphasis, and keep the aurora gradient exclusive to the logo.
