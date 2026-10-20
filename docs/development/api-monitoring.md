# API setup and monitoring verification

Both native apps offer subscription setup and API setup on first use. Codexex retains its existing ChatGPT device-code flow. Claudexex provides the documented `claude auth login --claudeai` command and Terminal launch so authentication completes inside unmodified Claude Code; the app consumes a sanitized user-selected quota export. Claudexex does not implement its own Claude.ai OAuth flow or collect subscription credentials.

## Documented public API monitoring

- Standard keys are checked through each provider’s public Models API using GET. This verifies access to that endpoint, not prepaid balance or future inference availability.
- An explicitly selected organization Admin key is required for organization usage/cost reports. Costs are reported spend, never remaining funds. No initial £2 balance is invented.
- Validated API credentials use separate device-only Keychain items for each product. Invalid checks do not persist a new key. Keys and provider response bodies are never displayed or logged. Preview, disconnect and cancelled setup invalidate pending results; a failed Keychain deletion stops monitoring and offers a retry.
- Reporting requests are read-only, pinned to the intended provider, reject redirects and disable cookies. OpenAI setup rejects Anthropic-key syntax before any network request. No model generation or coding request is part of monitoring.

## Optional unofficial dollars remaining

OpenAI's documented Models, Usage and Costs APIs do not establish a prepaid balance. Codexex therefore keeps public API validation/reporting separate from an optional private billing reader. The unofficial balance feature is disabled by default. A native alert must be accepted before its private requests or billing-session capture can run. The alert states that this is not an official or provider-approved method, may breach account terms, carries possible account restriction, suspension or ban risk, grants a session with account access, and can stop working when private endpoints change. This warning is not provider permission or a legal guarantee.

Affirmative consent is stored in the app/device preference `codexex.unofficialOpenAIBalanceConsent.v2`. Cancel leaves access disabled. An explicit Disable control cancels pending work, clears the displayed balance and prevents further session capture/requests without deleting an owner's Keychain credential. Revocation takes effect in memory even if preference persistence fails, including after Preview Mode is exited. The browser authorization closure and session-delivery callback recheck consent. Session setup is rejected before transport unless consent is active; previously stored sessions remain user-removable while disabled.

The low-level balance method defaults `allowUnofficial` to false and rejects before transport. Only enabled monitoring calls the pinned read-only GET `/v1/dashboard/billing/credit_grants` endpoint. The reader uses the actual `total_available` Decimal value, preserves zero and negative amounts, shows the fetch timestamp and labels its source unofficial. Missing/rejected/malformed values remain unavailable; costs, spending caps and an assumed £2 are never substituted. OpenAI billing remains linked as the account source of truth.

After consent, a separate WebKit browser with a dedicated persistent app-owned website data store opens the provider's billing page. Its main-frame observer captures only a `Bearer sess-…` authorization and same-request `OpenAI-Organization` scope sent to the permitted OpenAI billing API path. It does not read password fields, cookies, local storage or response bodies. The session is verified against the balance endpoint before an app-owned device-only Keychain credential is saved. This replaces the API reporting credential with a balance-only credential; reconnecting an API key restores public reporting. The selected billing organization is validated, persisted and supplied on balance requests. Manually entered tokens without a scope are labeled as the default billing organization.

Standard Models validation and organization Admin reports never invoke private billing while consent is disabled. When consent is enabled, a failed balance check does not undo separately successful public validation/reporting. Refresh is throttled to once per minute. Preview Mode, disconnect and consent withdrawal invalidate late results so cancelled work cannot save credentials or publish a balance.

An SDK is not itself permission to use an undocumented endpoint. No claim of provider approval or guaranteed freedom from account enforcement is made for this feature. Live billing sign-in compatibility remains unverified until a user completes provider sign-in and the actual endpoint accepts that account's credential.

## Historical live verification, 13 October 2026

Existing keys were retrieved from 1Password in a local process and passed only in memory to the production Swift clients. Both providers’ Models checks returned HTTP 200. Public organization-report checks returned OpenAI 403 and Anthropic 401; these keys cannot currently authorize organization monitoring. No secret was printed, written to a project file, or persisted to app Keychain during the test. No inference request was made. The approximately £2 balance remains unverified.

Earlier private OpenAI balance probes returned HTTP 403 with the existing standard key. The historical probe is not evidence that the opt-in automatic reader works with this account or is approved by the provider. No new live account requests are part of the consent-gate verification.

## Local checks

Focused API/client lifecycle tests cover read-only public requests, precise reported spending, safe errors, pagination, preview cancellation, validation-before-persistence, disconnect cancellation/removal failure, default-denied private requests, explicit consent, session scope, withdrawal while requests wait, failure to persist consent, and blocking stored billing sessions while consent is disabled. Mac and iOS builds are checked separately.

Two inherited Codexex footer-render tests failed on a clean HEAD baseline because their bright-green pixel assertions inherited the light system theme. Fixtures use isolated settings and explicitly request dark appearance; the original assertions are preserved.

The existing Codexex release-smoke preflight reports a missing `x86_64-apple-darwin` Rust target in the pre-existing stable toolchain. No toolchain changes were made. Local checks do not establish signed device behavior, App Store acceptance or provider approval.

Sources: [OpenAI Models](https://developers.openai.com/api/reference/resources/models/methods/list), [OpenAI usage](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions), [OpenAI costs](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs), [Anthropic Models](https://platform.claude.com/docs/en/api/models/list), [Claude Code CLI authentication](https://code.claude.com/docs/en/cli-reference), [Claude authentication boundaries](https://code.claude.com/docs/en/legal-and-compliance).

## Browser sign-in retention

The revised version-2 disclosure covers persistent browser sign-in. After acceptance, only the app’s dedicated WebKit cookie store is used; Safari, Chrome and other apps’ browser data are never imported. Cancel, closing a sign-in window, retrying, disabling monitoring and app restarts retain these cookies. Disable still cancels private requests and clears observed balances. Explicit removal of the saved browser/Console session and Reset App remove all website data from this dedicated store, including cookies. A first sign-in from an older temporary browser cannot be recovered after that browser closes. A successfully verified monitoring credential remains in device-only Keychain storage.
