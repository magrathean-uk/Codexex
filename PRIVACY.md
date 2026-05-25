# Codexex Privacy Policy

Last updated: 25 May 2026

Codexex is a local-first macOS and iOS companion for viewing Codex quota state, reset windows, local usage history, session burn, and forecasts.

The important bit: Codexex does not run a Magrathean cloud service for your quota data. The app talks from your device to OpenAI/ChatGPT services for sign-in, token refresh, and quota lookup, and to Apple platform services for App Store operation. Local history, preferences, preview-mode data, and account state remain on your device unless you choose to send material to us for support.

## Controller

MAGRATHEAN UK LTD., a company registered in England and Wales (Company No. 16955343) with registered office at 16 Caledonian Court, West Street, Watford, England, WD17 1RY is the controller for personal data we process for our website, support, security, licensing, App Store administration, and customer communications.

OpenAI, Apple, and any other third-party services you use with Codexex are separate controllers or providers for their own services. Your OpenAI/ChatGPT account, subscription, plan, quota, API responses, and account dashboard are controlled by OpenAI, not Magrathean.

## Data processed by Codexex on your device

Codexex may store or process the following on your device:

- ChatGPT/OpenAI sign-in state;
- OAuth access tokens, refresh tokens, account identifiers, email address, plan type, expiry times, and related authentication metadata;
- Codex quota snapshots, reset times, 5-hour, weekly, and 30-day history views;
- local Codex session usage data, project/model/session burn, cache-read pressure, tool-loop signals, model-overkill signals, and forecasts;
- preview-mode settings and sample preview data;
- appearance, onboarding, menu-bar, window, notification, and app preferences;
- local helper/XPC state needed by the macOS app and bundled helper;
- error messages and local logs visible on your machine.

OAuth tokens are stored using Apple Keychain or platform-protected storage. Local history and preferences are stored in the app sandbox or equivalent local storage.

## Data we do not collect from the app

Magrathean does not collect Codexex analytics, behavioural tracking, advertising identifiers, third-party ad data, cross-app tracking data, or quota history from the app.

Codexex does not send your OpenAI password to Magrathean. The app does not operate a relay for your OpenAI account or quota data. We do not sell personal data.

## Authentication

Codexex uses a ChatGPT/OpenAI sign-in flow. The app requests a device/user code, asks you to complete approval through the OpenAI/ChatGPT flow, exchanges the approved code for tokens, and refreshes tokens when required. The app uses those tokens to request quota and usage information for the signed-in account.

Your OpenAI password is handled by OpenAI's sign-in flow. Magrathean does not receive it.

## Network communication

Codexex may connect to:

- OpenAI/ChatGPT endpoints for authentication, token refresh, quota lookup, account selection, and related responses;
- Apple services for App Store distribution, purchase state where applicable, updates, platform crash reporting where handled by the operating system, and platform operation;
- Magrathean websites only when you open legal, support, release-notes, or product links;
- support channels only when you deliberately send us a message or support material.

OpenAI, Apple, your network provider, and any infrastructure between your device and those endpoints may process connection metadata such as IP addresses under their own terms and privacy notices. Magrathean does not receive that network metadata unless you contact us or use our websites.

## Support data

If you email us, open a support request, report a security issue, or send logs/screenshots, we process the contact details and content you provide so we can respond, troubleshoot, protect the product, and keep records of the request.

Do not send OAuth tokens, refresh tokens, private account data, source code, customer data, or regulated data unless we have agreed a secure support route.

## Legal bases

For personal data we process as controller, we rely on:

- contract where processing is necessary to provide requested app, support, licensing, or customer services;
- legitimate interests to operate, secure, improve, document, defend, and support Codexex;
- consent where required for optional communications;
- legal obligation where we must keep records, respond to lawful requests, or comply with accounting, tax, company, consumer, or data-protection duties.

## Sharing

We do not sell personal data and do not use app data for advertising.

We may use service providers for email, hosting, security, issue tracking, legal, accounting, App Store administration, and operational support. Where a provider processes personal data for us, we use appropriate contractual controls.

OpenAI and Apple process data independently when you use their services.

## International transfers

We primarily operate from the United Kingdom. OpenAI, Apple, hosting, email, security, and support providers may process data outside the UK or EEA. Where required by data-protection law, we use appropriate safeguards such as adequacy regulations or standard contractual clauses.

You can contact us for more information about the safeguards used for a relevant international transfer and, where applicable, how to obtain a copy of those safeguards.
## Retention

Local app data remains on your device until you clear it, sign out, remove the app, delete local history, or the operating system removes it.

OAuth tokens remain in Keychain or platform storage until sign-out, deletion, expiry, replacement, or app removal behaviour handled by the platform.

We keep support, security, legal, business, and communication records only for as long as needed for the purposes described in this policy, legal compliance, dispute handling, and auditability.

For controller records we hold, retention depends on the type of record and the risk involved. Support and customer communications are kept only while needed to answer the request, maintain the relationship, handle disputes, or preserve auditability. Security records are kept for investigation, defence, and abuse-prevention periods. Accounting, tax, company, contract, licensing, and business records are kept for the period required by law or for ordinary limitation periods, normally up to six years where relevant. We delete or anonymise records when they are no longer needed.
## Security

Codexex is designed around local storage, Apple sandboxing, Apple Keychain, a bundled helper/XPC model on macOS, no Magrathean quota relay, and no app analytics SDK. No method of storage or transmission is completely secure. You remain responsible for securing your device, Apple ID, OpenAI account, local logs, local history, backups, and any support material you send.

## App Tracking Transparency

Codexex does not track your activity across other companies' apps or websites for advertising or data-broker purposes and does not request Apple's App Tracking Transparency permission.

## Children

Codexex is not directed to children under 13. We do not knowingly collect personal data from children through the app.

## Automated decision-making

We do not make decisions about you based solely on automated processing, including profiling, that produce legal effects or similarly significant effects. Quota readings, reset timing, history, session-burn analytics, forecast values, warnings, and diagnostics are informational outputs for human review and do not replace OpenAI account records, invoices, dashboards, or contractual notices.

## Your rights

Under the UK GDPR and the Data Protection Act 2018, you may have rights to access, rectification, erasure, restriction, objection, portability where applicable, and withdrawal of consent where processing is based on consent.

To exercise rights against personal data we control, contact the email address listed below. We may need information to verify the request. Where the relevant data is controlled by your employer, customer, tenant owner, data-source operator, Apple, OpenAI, Microsoft, Google, TeslaMate, MyTeslaMate, a server owner, or another third party, you should direct the request to that controller.

You also have the right to object to processing based on our legitimate interests. This right applies to controller processing we carry out for support, security, product administration, business records, and similar purposes. We will stop that processing unless we can show compelling legitimate grounds that override your interests, rights, and freedoms, or unless the processing is needed for legal claims.

## Complaints

You may complain to the UK Information Commissioner's Office at `ico.org.uk/make-a-complaint`. We would prefer a chance to fix the issue first.

## Changes

We may update this policy. The "Last updated" date shows when the current version took effect. Material changes may be notified through the app, website, App Store listing, release notes, customer channel, or another appropriate route.


## Contact

Questions: `contact+codexex@magrathean.uk`.
