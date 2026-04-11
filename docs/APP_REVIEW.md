# App Review Notes

## What the app does

Codexex is a free macOS menu bar utility. It shows Codex quota and usage state in a compact menu bar UI.

## Login

The app supports:
- ChatGPT device-code sign-in in Safari
- Preview Mode for offline review

For ChatGPT sign-in:
1. Open `Settings`
2. Click `Sign In with ChatGPT`
3. Copy the device code shown in the app
4. Click `Open Safari`
5. Complete login in Safari
6. Wait for the app to finish sign-in automatically

Preview Mode:
1. Open the app on first launch
2. Choose `Preview Mode`
3. Review the full UI without credentials or network

## Data access

- No browser cookie scraping
- No private APIs
- No alternate browser support flow
- No hidden login flow
- No user file access outside sandbox model

## Review helper note

The app bundles an internal helper used only for sign-in and quota retrieval.
It is shipped inside the app bundle and sandboxed.

## Suggested reviewer path

1. Launch app
2. Open menu bar extra
3. Open `Settings`
4. Complete ChatGPT sign-in or use `Preview Mode`
5. Return to popup and review quota cards and history
