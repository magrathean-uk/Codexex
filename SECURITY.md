# Security Policy

## Reporting a vulnerability

Report a vulnerability privately to `contact@magrathean.uk` with the subject
`SECURITY: Codexex`. If GitHub presents a private vulnerability-reporting form
for this repository, it may also be used. Do not post credentials, private
keys, signing certificates, database dumps, or exploit details in public
issues.

Include the affected version or commit, platform, reproduction steps, expected
impact, and redacted evidence. The repository does not establish a response or
remediation-time commitment.

## System and scope

Codexex is a macOS menu bar app with an iPhone and iPad companion that reads
Codex quota state. Its security-sensitive surfaces include ChatGPT device
authentication, token storage, local quota and session data, the macOS helper
and XPC bridge, and the optional iOS APNs wake registration.

The macOS app communicates with a bundled Rust helper through
`Sources/CodexexXPCService/`. The XPC listener sets a code-signing requirement
outside its debug-only development bypass. The helper's device-auth state and
the iOS companion's tokens and pending auth records use platform-protected
storage. The optional iOS wake registration keeps an installation credential in
Keychain; the device sends the APNs device token to the configured wake endpoint.

## Security properties

- Authentication tokens, refresh tokens, device codes, and account identifiers
  must not be exposed through logs, errors, analytics, or the wake service.
- The macOS XPC service must accept only the intended signed client in release
  builds, and helper requests must not permit arbitrary process execution.
- Device-auth state and XPC requests must validate untrusted values and bound
  stored or parsed data.
- The iOS wake path is content-free. It must not send quota values, OpenAI
  credentials, account identity, or usage history to the wake service.
- Privileged or security-scoped local file access must remain limited to the
  user-approved resource and be released after use.

## Reportable findings

Report findings with realistic reachability and impact, including token or
account-data disclosure, XPC client-authentication bypass, unauthorized helper
execution, authentication-flow manipulation, unsafe handling of local
security-scoped data, or a wake service request that exposes account or quota
content. Denial of service, privacy, and integrity issues are reportable when
they affect a supported app or helper path.

This policy describes source-level intent. It does not prove that a build,
deployment, Cloudflare relay, APNs delivery, signing configuration, or platform
control is operating as intended.

## Scope & Safe Harbour

Magrathean UK Ltd. will not pursue a good-faith researcher for security disclosures that:

- Target non-production test systems or researcher-owned environments;
- Avoid persistence, destructive changes, denial of service, and access to
  personal or customer data;
- Report promptly and permit reasonable time for remediation;
- Do not condition non-disclosure on financial compensation.

## Excluded Conduct

No safe harbour covers phishing, credential stuffing, accessing private production infrastructure, large-scale scanning, denial of service, or unlawful conduct.

## Limitations

The checkout shows an optional `push.magrathean.uk` integration but does not
establish its deployed configuration or whether GitHub private reporting is
enabled. Treat those as deployment questions rather than source-level
assurances.
