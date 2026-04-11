# App Review Notes

## What the app does

Codexex is a free macOS menu bar utility. It shows Codex quota and usage state in a compact menu bar UI.

## Login

The app supports:
- ChatGPT device-code sign-in in Safari
- API key mode

For ChatGPT sign-in:
1. Open `Settings`
2. Click `Sign In with ChatGPT`
3. Copy the device code shown in the app
4. Click `Open Safari`
5. Complete login in Safari

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
4. Complete ChatGPT sign-in or enter API key
5. Return to popup and review quota cards and history
