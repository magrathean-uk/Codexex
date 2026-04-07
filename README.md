# CodexMeter

Pure Swift 6 menu bar app for macOS 26+ that shows **Codex** quota usage only.

It does **not** monitor Claude or other providers.
It reuses the existing cached authentication that the official **Codex app / Codex CLI / Codex IDE extension** already use, via the official `codex app-server` JSON-RPC interface.
No second login flow is built into this app.

## What it shows

- Codex usage bucket
- Codex Spark usage bucket when Codex exposes it as a separate rate-limit bucket
- Reset time for each bucket
- Relative time until reset
- Account email / plan when available
- Last successful refresh time
- Exact executable path being used

## Design choices

- One account only
- No browser scraping
- No cookie theft
- No webview login
- No long-lived daemon process
- Very small steady-state RAM use: each refresh launches `codex app-server`, reads two JSON-RPC methods, then exits
- Wake-from-sleep refresh to avoid stale quota/reset data
- Liquid Glass styling for macOS 26+ custom cards

## Auth source

`CodexMeter` does **not** read or parse tokens itself.
Instead it asks the official Codex binary for account and rate-limit state.

That means it can reuse whichever credential store Codex is already using:

- `~/.codex/auth.json`
- OS credential store / keychain
- bundled Codex app binary auth state
- Codex CLI auth state

## Important limitation

There is no documented public source proving that the standalone ChatGPT macOS app exposes a reusable local Codex auth cache to third-party apps.
So this project supports the **official Codex auth path** only.
If your ChatGPT account is also the one you use inside Codex, and Codex is already signed in, this app works without another login.

## Binary discovery order

1. `CODEXMETER_CODEX_PATH`
2. `codex` found on `PATH`
3. Common manual locations:
   - `/opt/homebrew/bin/codex`
   - `/usr/local/bin/codex`
   - `~/bin/codex`
   - `~/.local/bin/codex`
   - `/Applications/Codex.app/Contents/Resources/codex`
   - `~/Applications/Codex.app/Contents/Resources/codex`

## Build

```bash
swift build
```

Generate the Xcode project from `project.yml`:

```bash
xcodegen generate
```

On macOS 26+:

```bash
swift run CodexMeterApp
```

Open in Xcode if you prefer:

```bash
open CodexMeter.xcodeproj
```

## Notes

- If you are signed in to Codex with an API key instead of ChatGPT, ChatGPT quota buckets may not exist.
- If Codex is not installed or not signed in, the app shows a precise error in the popover.
