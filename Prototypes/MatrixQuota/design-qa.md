# Matrix theme design QA

Source visual truth: local reference asset `Digital_rain_animation_medium_letters_shine.gif` (500 × 400 px). The source asset is not committed to this repository.

Implementation captures: `/tmp/codexex-matrix-crisp-a.png` and `/tmp/codexex-matrix-crisp-b.png` (1206 × 2622 px each).

Viewport: native iPhone 17 Pro simulator, 402 × 874 pt at 3× density. The source is a landscape crop and the implementation is a full portrait screen, so the rain-field region—not the surrounding frame—was compared at matched visual scale.

State: Matrix theme enabled; preview quota 32%; initial rain speed 100%; two captures one second apart.

**Findings**

- No actionable P0/P1/P2 differences. The native field now matches the target's medium, crisp green columns, dark trails, intermittent bright green/white heads, and black ground without blur.

**Open Questions**

- Physical-device confirmation remains for touch-drag feel and gyro response; simulator captures cannot prove either hardware interaction.

**Implementation Checklist**

- [x] Start at the previous maximum rain speed.
- [x] Hide a vertical drag control: pull down to 50%, pull up to 100%.
- [x] Remove glyph blur while retaining bright leading characters.
- [x] Preserve the Matrix page's only visible control: Settings.

**Fidelity surfaces**

- Fonts and typography: passed. Medium monospaced glyphs are sharp, legible, and substantially less frenetic than the prior per-frame cycling; the percentage remains the only display type.
- Spacing and layout rhythm: passed. Narrow columns fill the submerged region without crowding the percentage or the Settings target.
- Colours and visual tokens: passed. Near-black base, vivid phosphor green trails, and sparse pale heads match the GIF's contrast structure.
- Image quality and asset fidelity: passed. This is live Canvas output rather than a blurred bitmap; captures retain hard glyph edges.
- Copy and content: passed. The screen contains only the quota percentage and Settings as requested.

## Comparison evidence

- Full view: the GIF and the two native screenshots were viewed together. The native rain advances between the captures while keeping stable, unblurred character edges.
- Focused rain region: checked for medium glyph scale, tight vertical columns, dark trail fade, and white/green heads. No separate focused crop was needed because these features are readable in the shared comparison.

## Comparison history

1. Earlier Matrix rain was too fast and character cycling made it visually soft. The renderer now changes glyphs at 6–12 Hz and keeps every glyph unblurred.
2. Added a hidden, cumulative vertical drag speed control, clamped to 50–100% of the former speed; screenshots captured after the renderer update show the revised motion style.
3. Post-fix comparison found no actionable P0/P1/P2 visual differences for the requested GIF-inspired animation.

## Follow-up polish

- P3: tune the hidden drag sensitivity on physical iPhone and iPad hardware if it feels too coarse.

Final result: passed.
