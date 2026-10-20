# Codexex and Claudexex iOS design review

Reviewed 14 October 2026 against the current Apple Human Interface Guidelines, using the installed iOS 27 SDK/runtime. The screenshots are native production SwiftUI view bodies hosted in UIKit with isolated sample observations and provider dependencies.

## Flow results

| Step | Health after changes | Evidence and resulting behavior |
| --- | --- | --- |
| 1. First launch | Checked | Native grouped choices separate subscription sign-in, API monitoring and sample preview. Setup starts from an explicit selection. |
| 2. Subscription sign-in | Improved | Codex exposes copied/expired-code feedback. Claude separates Safari instructions, private code entry, checking and retry. Code focus follows an explicit Safari return; normal foreground returns respect keyboard dismissal. |
| 3. API key setup | Improved | Short Standard/Admin choices remain legible at accessibility sizes. Keyboard submission and dismissal use guarded native actions. Rejected input remains available to correct; successful verification clears it. Progress, connected and error states are distinct. |
| 4. Balance and reports | Improved | Codex's balance row stacks at large text sizes instead of splitting the amount. Errors use an icon with semantic text. Reports distinguish loading from unavailable data. Money retains two decimal places. |
| 5. Quota dashboard | Improved | Native navigation title and toolbar replace the scrolling header. Accessibility typography keeps reset times on one line. Short allowance text reduces density; secondary details remain scrollable. |
| 6. Settings and history | Improved | Native account, appearance, Live Activity, data and about groups. New installs follow system appearance; existing choices persist. Pushed Settings uses the native back action. “Show history” now controls a separate Usage history entry on the current dashboard. |
| 7. Home Screen widgets | Improved | Small/medium quota and API states cover fresh, stale and empty data. Large text gets three focused rows. Empty copy directs people to open the app. Accessibility summaries retain full observation and reset dates. |
| 8. Live Activity | Improved | Compact accessibility layouts retain weekly/five-hour values and freshness within the tested bounds. Claude uses orange branding. Full reset and check timestamps remain available in accessibility values. |

## Confirmed findings repaired

1. Codex Settings split “ChatGPT” into fragments at accessibility text size 3. Account status now stacks under the name. The same adaptive pattern preserves complete prepaid amounts.
2. Both dashboards wrapped the final digit of the reset time onto another line. Accessibility sizes now use semantic hero typography and a single-line time; ordinary sizes retain the prominent reset clock.
3. The scrolling dashboard header duplicated custom navigation controls. Settings and refresh now use native toolbar items with labelled touch targets.
4. Claude's plain orange actions were too pale on white. Both apps use appearance-aware action colours and darker prominent-button fills. The tested solid colour pairs are approximately 6.68:1/7.05:1 on white and 8.27:1/7.46:1 on the dark grouped background, for Codex/Claude respectively. These calculations cover those specific pairs, not every composited colour in the app.
5. Key entry lacked consistent keyboard/retry feedback; explicit white disabled text was nearly invisible in light mode. Disabled labels now use semantic foregrounds. The Admin choice and known invalid-key message are shorter.
6. “Show history” did not affect the default signed-in dashboard. It now exposes a separate native history destination without expanding the main page.
7. Large-text widget and Live Activity layouts clipped labels and lower rows. Shorter bounded layouts retain their primary value and freshness. Claude's Live Activity also inherited the wrong green accent.
8. The complete iOS suites exposed duplicate API credential removal during Reset and duplicate Codex background scheduling during preflight. Reset now uses the injected monitor once, including in Preview mode, and reports removal failure while clearing other local data. The background handler schedules its next attempt once. Regression tests retain the original assertions and isolate provider stores/transports.

## Evidence and validation

| Finding | Baseline screenshot | Final screenshot |
| --- | --- | --- |
| Fragmented account name | [Codex Settings, large text](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/before/codexex/settings-iphone-ax3-light.png) | [Adaptive account rows](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/after/codexex/settings-iphone-ax3-light.png) |
| Split balance amount | [Codex API, large text](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/before/codexex/api-landing-iphone-ax3-light.png) | [Complete amount](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/after/codexex/api-landing-iphone-ax3-light.png) |
| Wrapped reset time | [Claude dashboard, large text](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/before/claudexex/claudexex-before-dashboard-accessibility3-light.png) | [Single-line time](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/after/claudexex/claudexex-before-dashboard-accessibility3-light.png) |
| Pale action text | [Claude Safari introduction](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/before/claudexex/claudexex-before-oauth-introduction-phone-light.png) | [Readable action](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/after/claudexex/claudexex-before-oauth-introduction-phone-light.png) |
| Dense small widget | [Codex quota widget, large text](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/before/codexex/codexex-widget-subscription-fresh-small-ax3.png) | [Focused three rows](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/after/codexex/codexex-widget-subscription-fresh-small-ax3.png) |
| Activity overflow | [Codex expanded activity, large text](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/before/codexex/codexex-live-activity-used-stale-expanded-ax3.png) | [Complete bounded content](/Users/bolyki/.codex/visualizations/2026/10/14/codexex-claudexex-hig-review/images/after/codexex/codexex-live-activity-used-stale-expanded-ax3.png) |

The gallery preserves original PNG bytes and includes a SHA-256 manifest. The accepted baseline contains 200 app screens and 80 corrected widget/Live Activity captures. The initial widget harness produced incorrect viewport clipping; those images were rejected. The final harness asserts exact content bounds. Settings-bottom captures target the actual final native list item and wait for stable layout.

App fixtures cover standard phone (393×852), narrow phone (375×667), tablet width (1024×768), and phone accessibility text size 3, each in light and dark appearance. Widget fixtures cover small/medium, standard/accessibility text, quota/API, and fresh/stale/empty. Live Activity fixtures cover used/remaining, fresh/stale, and Lock Screen/expanded content bounds.

The delivered gallery contains 280 accepted baseline images and 352 final images (144 Codex app, 128 Claude app, 80 widget/Live Activity). All 80 final widget originals received visual inspection after the renderer was stabilized with a visible key window and bounded layout settling. Superseded incomplete renders are excluded from the delivered image set.

Validation passed:

- Codex: 113 XCTest cases and seven Swift Testing cases, including native capture and reset/background regressions.
- Claude: 132 non-capture XCTest cases in the final complete verification pass, plus its two passing native capture cases. Stale copied text/URL expectations were updated without relaxing behavior assertions.
- Both iOS app and widget targets build in Release for generic iOS devices with signing disabled.
- Both repository diff checks and gallery JavaScript syntax/reference/hash checks pass.
- All disposable simulator devices recorded for this review were removed by Clean Development. The simulator owned by another task was preserved.

The final passing Codex result is `d7d7d28d-e6d4-4545-845d-6db9e6b5c2b9`; Claude behavior verification is `362bdfcb-fb88-4855-8db5-a66d615a6c86`; the final widget capture is `c71664db-a958-4697-b609-3d9c02d39c15`. Native Claude app captures are retained in `c0890e77-34bb-43aa-8655-bfb564f5c2ae`; that earlier run reported the stale expectations and stalled during diagnostic collection after the test summary. Its capture cases passed. Diagnostic collection was disabled for the successful verification run.

Environment checks pass. Global project checks retain two pre-existing third-party issues (`gopro-gpr` policy marker; `groma.md` markers/global-install references). The home audit retains six existing entries (`.aws`, `.claude-science`, `.gemini`, `.opencode`, `.cache/antigravity`, `.local/bin/agy`). There are no new home-audit entries relative to this task's baseline. Unrelated maintenance removed the earlier extra Antigravity backup and two project findings while this review ran.

## Limits

The app fixtures render exact production views and mocked states; they are not recordings of a complete tapped journey. Provider web pages, live credentials, paid quota, passkeys and network acceptance were outside this design run. The embedded browser fallback received a source-level navigation/layout repair without loading a provider page.

Tablet-width hosting is not a physical iPadOS check. Widget and Live Activity bodies were rendered at fixed bounds, not installed into every system presentation mode. Home Screen tinted rendering and actual compact/minimal Dynamic Island hosting remain device checks. These tests do not establish APNs delivery or background-update timing. Codex's history-screen capture uses one observation, so it does not validate multi-day chart labels.

Motion guards were inspected in source. Animations were disabled for stable screenshots; this is not a device exercise of Reduce Motion. VoiceOver summaries were improved in source; spoken order, hardware keyboard use, Increased Contrast and all accessibility sizes/languages still need interactive device validation. No blanket accessibility or HIG certification is claimed.

## Apple references

The native layout and materials changes follow Apple's [iOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios), [navigation](https://developer.apple.com/design/human-interface-guidelines/navigation-and-search), and [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials).

The setup/settings changes follow [onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding), [settings](https://developer.apple.com/design/human-interface-guidelines/settings), [buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), and [text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields).

Adaptive text and motion follow [typography](https://developer.apple.com/design/human-interface-guidelines/typography), [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), and [motion](https://developer.apple.com/design/human-interface-guidelines/motion). Bounded presentations follow [widgets](https://developer.apple.com/design/human-interface-guidelines/widgets) and [Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities).
