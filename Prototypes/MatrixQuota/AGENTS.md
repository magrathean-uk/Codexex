# MatrixQuota prototype context

The MatrixQuota prototype is React. SwiftUI and gyro details below describe its native counterpart. Commands run relative to `Prototypes/MatrixQuota`.

## Command reference

```sh
npm run check:runtime
npm run dev
npm run build
npm run test:sites
```

`check:runtime` checks recorded runtime hashes. `dev` starts the local preview. `test:sites` covers the Sites worker. Generated mock images provide references for layout, component anatomy, density, spacing, colour, typography, content, and hierarchy.

## Matrix theme reference

- The Matrix page displays the live percentage, code-fill surface, and a Settings button.
- Settings > Display contains `Matrix theme` and `Show used quota` switches. Matrix theme persists through navigation. The gear opens Settings; the back action returns to Matrix with the switch still on. Disabling Matrix theme returns to the normal theme.
- Settings uses green native toggles. `Show used quota` has a `Quota` section immediately after `Account`. Privacy has `Privacy Policy` and `Terms of Service` globe/external-link rows linked to Codexex pages.
- Live Activity has a section directly after `Quota`, with a standard-height start/stop row. The same start/stop action appears on the normal dashboard. `Show used quota` immediately updates a running Live Activity's content state, switching its Lock Screen/Dynamic Island text and progress between remaining and used quota.
- Show used quota defaults off: a 9% balance reads `9% left`; when on, it reads `91% used` and inverts the standard quota fill and Matrix code-fill surface. Matrix rain continues downward, with every track starting above the device's top edge.
- Code rain follows the supplied GIF and track model: sparse medium-weight finite columns, stable glyphs, a white leading head at the bottom of each track, and green fading tails above it. Tracks fall one character every 0.15 seconds at the default GIF-calibrated speed. The native display uses an adaptive 120 fps SwiftUI animation schedule and gyro data sampled at 30 fps, independent of SwiftUI redraws.
- A hidden vertical drag ranges from 50% on pull-down to 100% on pull-up. A hidden horizontal drag maps left to 0% density and right to 100%. At 100%, every safe grid cell below the waterline is filled without glyph overlap. Phone tilt moves the code surface; horizontal gyro is inverted so a left tilt shifts water left. The water wave has a 6.5 pt amplitude. iPhone orientation is portrait; iPad supports landscape.
- A display-owned render clock reads the latest gyro sample while rendering. Code and gyro pause while inactive or with Reduce Motion enabled. Canvas paints opaque black and presents asynchronously.
- The Matrix percentage is displayed on a 15% ultra-thin-material frosted capsule with a near-invisible white edge.

## Source map and runtime references

- `src/Prototype.tsx` and `src/prototype.css` contain app-specific UI.
- `src/App.tsx`, `src/main.tsx`, `src/styles.css`, `src/mobile/`, `public/assets/iphone/`, `public/assets/android/`, and `public/assets/status/` contain the mobile runtime and assets.
- `vite.config.ts`, `worker/index.js`, and `scripts/prepare-sites-build.mjs` provide preview, worker, and Sites build integration.
- `RUNTIME-CONTRACT.md` describes the phone frame, status bar, scrolling, keyboard, carousels, bottom sheets, pointer interaction, FlowStack, MobileScroll, Carousel, and drag behaviour.
- `src/mobile/COMPONENTS.md` is the component and gesture reference.
