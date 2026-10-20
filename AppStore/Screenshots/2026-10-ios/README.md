# Codexex iOS App Store screenshot design

Seven real native screens, in store order, use the source stems in `design.json`. Raw iPhone images must be 1320 × 2868; raw iPad images must be 2064 × 2752. Both sets use the same concise captions and a small **Sample data** disclosure. No balances, quota percentages or other UI content are changed by this pipeline.

The background is neutral charcoal with a restrained green gradient, matching the quota dashboard. Headlines are white; supporting text is muted. Apple Frames supplies the device bezel. No built-in themed preset is selected.

## Framing

The installed `asc-screens` renderer draws its default captions before a large centered frame, which can cover the captions. The per-shot configs therefore request plain framing. `frame-store.py` invokes those configs noninteractively in the routed scratch directory, reuses the actual transparent frame output, and composes it inside reserved headline, subtitle and disclosure margins. Installed tools remain unchanged.

From the Codexex repository root:

```zsh
source "$HOME/dev/machine/env.zsh"
FRAMES_ASSETS="${BOLYKI_DEV_LIBS:?}/frames-apple401" \
clean-development run --session session-only -- \
  python3 AppStore/Screenshots/2026-10-ios/frame-store.py \
  --raw-dir AppStore/Screenshots/2026-10-ios/raw \
  --output-dir AppStore/Screenshots/2026-10-ios/framed-next
```

Alternatively use `--raw-dir PATH` for a directory containing `iphone/` and `ipad/`. `--dry-run` prints the source mapping and caption copy without writing or rendering. Runtime staging and config receipts stay under the selected cache’s scratch directory. Final images and `review.json` are durable deliverables under the chosen output directory.

The script checks source dimensions, requires every frame, and verifies all 14 final PNGs have the expected dimensions and no transparency. It refuses to overwrite existing final images. Inspect every output before upload. This pipeline does not capture, log in, build, install or upload anything.

The current reviewed set is `framed-final/en-US/`, with seven images per device
family. Open `index.html` for the full gallery and What's New. Original native
captures are retained in `raw/`; `framed-final/review.json` records their hashes.

