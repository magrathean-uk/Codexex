# Mobile Prototype Agent Guide

## Local workflow

Run commands from `Prototypes/MatrixQuota`. Run `npm run check:runtime` before
a preview, then use `npm run dev` for the local preview. Inspect the rendered
screen and its primary interactions. Do not deploy or publish unless the
current task authorizes it.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

The Matrix decisions below are product and reference decisions. SwiftUI and
gyro details describe the native counterpart; this prototype remains React.

## Matrix Theme Decisions

- The Matrix page contains only the live percentage, the code-fill surface, and one Settings button.
- Settings > Display owns `Matrix theme` and `Show used quota` switches. Matrix theme persists through navigation; the gear opens Settings and a back action returns to Matrix while the switch remains on. Disabling Matrix theme returns to the normal theme.
- Settings uses green native toggles. `Show used quota` is its own `Quota` section immediately after `Account`. Privacy contains only `Privacy Policy` and `Terms of Service` globe/external-link rows, linking to Codexex pages.
- Live Activity has its own section directly after `Quota`, with a standard-height start/stop row. The same start/stop action lives on the normal dashboard. `Show used quota` immediately updates a running Live Activity's content state, so its Lock Screen/Dynamic Island text and progress switch together between remaining and used quota.
- Show used quota defaults off: a 9% balance reads `9% left`; on, it reads `91% used` and inverts the standard quota fill and Matrix code-fill surface. This never reverses Matrix rain: every track starts above the device's top edge and falls downward.
- Code rain follows the supplied GIF and track model: sparse medium-weight finite columns, stable glyphs, a white leading head at the bottom of every track, and green fading tails above it. Tracks fall down one character every 0.15 seconds at the default GIF-calibrated speed. The display uses an adaptive 120fps SwiftUI animation schedule, while gyro data samples at 30fps without triggering SwiftUI redraws. A hidden vertical drag ranges from 50% on pull-down to 100% on pull-up. A hidden horizontal drag maps left to 0% density and right to 100%; at 100% every safe grid cell below the waterline is filled, without glyph overlap. Phone tilt moves the code surface: horizontal gyro is inverted so a left tilt shifts water left. The water wave uses a 6.5pt amplitude. iPhone remains portrait-only; iPad permits landscape.
- Battery: one display-owned render clock. Read the latest gyro sample while rendering; never trigger extra SwiftUI redraws for motion. Pause code and gyro whenever inactive or Reduce Motion is on. Canvas paints opaque black and presents asynchronously.
- The Matrix percentage is always legible on a 15% ultra-thin-material frosted capsule with a near-invisible white edge.

## Editing Boundary

- Build app-specific UI in `src/Prototype.tsx` and `src/prototype.css`.
- Treat `src/App.tsx`, `src/main.tsx`, `src/styles.css`, `src/mobile/`, `public/assets/iphone/`, `public/assets/android/`, `public/assets/status/`, `vite.config.ts`, `worker/index.js`, and `scripts/prepare-sites-build.mjs` as protected runtime files. Do not edit, replace, remove, or recreate them unless the user explicitly asks to change the mobile runtime itself. For an explicit runtime change, update the affected lock hashes only after verifying the new runtime behavior.
- Run `npm run check:runtime` before preview or handoff. If it fails, restore the protected runtime instead of weakening or bypassing the check.
- `npm run build` must preserve the mobile runtime. Run `npm run test:sites` when changing the worker or preparing a user-requested Sites handoff. Do not replace this project with a Vinext starter.

## Moved detail

Read `RUNTIME-CONTRACT.md` before changing the phone frame, status bar, scrolling, keyboard, carousels, bottom sheets or any pointer interaction: it holds the protected-runtime contract (FlowStack, MobileScroll, Carousel, keyboard and drag rules). `src/mobile/COMPONENTS.md` has the component and gesture reference. The editing boundary above still applies.

## Working practice

Preserve the protected runtime and existing visual decisions. Make changes only in
the app-owned files unless the user explicitly authorizes a runtime change. Run
`npm run check:runtime` before preview or handoff, and run the smallest relevant
check after a change. Do not deploy or publish unless the user asks.
