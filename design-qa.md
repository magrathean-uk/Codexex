# Reset dashboard design QA

**Findings**

- No actionable P0/P1/P2 visual mismatch in the dark, signed-in dashboard. The user-requested OpenAI sentence and the two horizontal separators are absent.
- Expected content differences: the reference contains sample reset times and percentages, while the app displays the connected account's live values. A Settings button was retained so the existing account and Live Activity controls remain reachable. The app also respects a saved Light appearance preference; the dark comparison used a non-persistent launch argument and did not change that preference.

**Evidence and comparison**

- Source visual truth: the supplied concept image `exec-9e8ee3d0-da26-4e34-87e1-502177060de7.png` from the Codex generated-images store (853 × 1844 px).
- Rendered implementation: `/tmp/codexex-reset-after-final-dark.png` (1320 × 2868 px, physical iPhone 17 Pro Max, 440 × 956 pt at 3×).
- State: signed in with real quota data; dark appearance; main dashboard at rest. The reference is a concept with sample data and no device status bar.
- Normalization: cropped 180 px of OS status-bar area from the device capture, resized its 1320 × 2688 px app-content region to 853 × 1737 px, then padded to 853 × 1844 px. This aligns content width and removes device chrome; the source has no independent CSS viewport or device-scale factor.
- Initial full-view, same-input comparison: `/tmp/codexex-reset-qa-final.png` (source left, normalized implementation right). Header, reset hierarchy, mint accent, original calendar tile, weekly allowance and footer were inspected together.
- Focused-region comparison was unnecessary: headline, original calendar, small copy and icons remained legible in the full-view comparison.

**Fidelity surfaces**

- Typography: native system font reproduces the bold headline, oversized time and quieter secondary labels; the sample and live values have different widths but do not truncate.
- Spacing/layout: left alignment and main section rhythm follow the reference. Removing the requested divider and copy leaves intentional open space before the weekly section and footer.
- Colors/tokens: near-black background, white primary text, grey secondary text and mint-green accent match the dark reference closely. The Light variant is an existing user-selectable appearance, not the comparison target.
- Image/icon assets: the reference has no custom illustration or photo. The refresh and Settings controls use native SF Symbols. The original calendar tile was native UI and was removed in the follow-up at the user's request.
- Copy/content: all requested labels and data roles appear. The OpenAI provenance sentence, both separators, and concept-only “Sample data” caption are omitted. Reset values come from the current account rather than the sample.

**Comparison history**

- Initial device comparison: the layout matched, but a failed refresh could have fallen back to the legacy graph screen. The root now retains the reset dashboard whenever a snapshot exists and shows an inline stale-data warning. After that fix, the signed device build was reinstalled and captured as `/tmp/codexex-reset-after-final-dark.png`; the final same-input comparison is `/tmp/codexex-reset-qa-final.png`.
- The phone's saved Light preference made the ordinary-launch capture light (`/tmp/codexex-reset-after-final.png`). A one-launch `-ios.appearanceMode dark` argument produced the dark comparison without overwriting the saved preference.

**Verification and remaining gap**

- Signed physical-device build, in-place installation, launch and screen capture succeeded. The dashboard displayed live reset times and percentages. Refresh and Settings controls are wired in code; their taps were not separately automated in this pass.
- No remaining visual P0/P1/P2 findings. A persistent dark appearance on this phone requires selecting Dark in the app's existing Appearance setting.

**Follow-up: Plus and Pro hierarchy**

- The user requested removal of the duplicate weekday/date square and a Pro layout led by weekly progress rather than a reset clock. These requested changes supersede the original reference where they conflict.
- Latest Plus capture: `/tmp/codexex-plus-no-calendar.png` (1320 × 2868 px, physical iPhone with live account data). The weekly reset is shown once as “Wednesday 30 September” plus time; the 5-hour reset remains the hero.
- Latest Pro capture: `/tmp/codexex-pro-reset-preview.png` (1320 × 2868 px, iPhone 17 Pro Max simulator with debug-only Pro preview data). The weekly percentage and progress bar lead; the reset date/time appears below, without a repeated weekly allowance row.
- Same-size Plus/Pro comparison: `/tmp/codexex-plus-pro-final.png`. Both use the same header, dark colors, typography, left alignment and secondary reset section. No date square is present in either capture. Important copy and bar detail are legible in this full-view comparison, so no focused crop was needed.
- The iOS app built for simulator and signed physical device, and the updated build was installed and launched on the phone. The focused Pro data test target compiled with `build-for-testing`; Xcode stalled before test execution, so that test is not claimed as passed. The simulator-rendered Pro branch and physical-device Plus branch were visually verified.

**Implementation checklist**

- [x] Implement the selected reset dashboard in SwiftUI.
- [x] Remove the specified sentence and two separators.
- [x] Compare the selected source and final device capture in one normalized image.
- [x] Rebuild and reinstall after the stale-refresh-state fix.

final result: passed
