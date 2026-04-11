# Codexex Glass Overhaul Design

## Goal

Bring `Codexex` to a cleaner macOS 26+ look with a hybrid glass direction:

- native macOS structure first
- glass only on important surfaces
- no scrolling in Settings
- tighter popup hierarchy
- preserve reliable menubar behavior

## Design Direction

Use a hybrid design:

- `Settings` keeps a native window and native control density
- `Popup` keeps stronger glass treatment because it is the product surface users see most
- standard controls stay standard: toggles, segmented control, labels, buttons
- custom glass appears only on grouped surfaces, not behind every row

This avoids the current problem where the app looks half-custom and half-system.

## Window And Scene Structure

- Keep the small `AppKit` shell for menubar left-click popup and right-click menu
- Keep `SwiftUI` for popup content and settings content
- Do not expand `AppKit` into the whole interface
- Keep `Settings` as the system settings window entry point

Reason:

- menubar interaction is more reliable with `AppKit`
- visual content is faster and cleaner in `SwiftUI`

## Popup Redesign

### Layout

- Top: Codex and Spark cards
- Middle: optional history card
- Bottom: small footer row with refresh, settings, and last-updated text

### Card Style

- Each quota card becomes one glass plate
- Inside each plate, each window row becomes a softer inset panel
- Progress bars stay custom but slimmer and calmer
- Blue remains the only strong accent color

### Typography

- stronger title/value contrast
- smaller metadata text
- all percentages stay monospaced

### Motion

- keep subtle numeric and progress animations
- no extra bounce or oversized transitions

## Settings Redesign

### Layout

Settings becomes a fixed, non-scrolling window with three blocks:

1. Account
2. Behavior
3. Status

### Visual Treatment

- one stronger glass account card
- one glass behavior card containing native rows
- one lighter status card
- no `Form` chrome and no fake full-window blur slab

### Content Rules

- short labels only
- helper text only where needed
- segmented refresh control stays compact
- device code appears only during sign-in
- no diagnostics block

### Sizing

- fixed width around 460 to 500 pt
- fixed height sized to content
- no scroll view

## Color And Material Rules

- use system-adaptive foreground colors
- use `.glassEffect` / material-backed surfaces only on cards
- avoid opaque custom backgrounds
- avoid tinting whole surfaces
- only action states and progress fills get blue emphasis

## Implementation Plan Shape

1. Replace current settings `Form` with a custom native-feeling stacked layout
2. Tighten popup glass hierarchy and inset panels
3. Tune spacings, radii, and control sizes for macOS density
4. Keep the tiny `AppKit` status item bridge
5. Rebuild and verify popup/settings behavior live

## Risks And Guardrails

- Too much glass will look fake fast
- Too much custom layout in Settings will drift away from macOS
- Expanding `AppKit` further is unnecessary unless a specific interaction requires it

Guardrails:

- system controls first
- custom glass second
- no all-over blur
- no decorative color noise

## Acceptance Criteria

- right-click menu still works
- settings opens reliably
- popup closes before settings opens
- settings does not scroll
- popup feels tighter and more premium
- app still reads as a native macOS utility, not a web-style mockup
