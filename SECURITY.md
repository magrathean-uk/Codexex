# Security Policy

Magrathean UK Ltd. takes the security of its software seriously. Thank you for helping keep our products and our users safe.

## Reporting a vulnerability

If you discover a security issue in Codexex, please **do not** open a public issue or pull request. Report it privately by email instead:

- Email: contact@magrathean.uk
- Subject: `[SECURITY] Codexex: <short description>`

Where possible, please include:

1. The version, build number, or commit SHA you are reporting against.
2. A clear description of the issue and its potential impact.
3. Reproduction steps, proof-of-concept, or test code where possible.
4. Any suggested mitigation or remediation.

## Our commitments

When you report a vulnerability in good faith, we commit to:

- Acknowledging receipt within five (5) UK working days.
- Triaging the report and providing an initial assessment within fourteen (14) days.
- Keeping you informed of remediation progress for material issues.
- Coordinated disclosure: we will agree a public-disclosure timeline with you, normally not less than ninety (90) days from acknowledgement.

For issues affecting authentication, token handling, the XPC bridge, or the bundled Rust helper, we will prioritise triage and aim to ship a fix or mitigation within thirty (30) days of confirmed reproduction.

## Scope

In scope:

- Source code in this repository, including the SwiftUI/AppKit shell, the XPC service, and the bundled Rust helper under `Helper/CodexexHelper/`.
- Application binaries published by Magrathean UK Ltd. that correspond to this repository (in particular, App Store builds of Codexex).
- The Magrathean UK web pages directly supporting this product (privacy, terms, app landing).

Out of scope:

- Third-party services, dependencies, or platforms that the software interoperates with (OpenAI, ChatGPT, Apple, the openai/codex upstream Rust crates). Please report those to the relevant vendor.
- Issues caused by user-side configuration that does not match the documented setup.
- Issues caused by changes in upstream OpenAI APIs or terms.
- Best-practice or hardening recommendations that do not constitute exploitable vulnerabilities.

## Safe harbour

We will not pursue civil or criminal action against good-faith security researchers who:

- Stay within the scope above.
- Make a reasonable effort to avoid privacy violations, destruction of data, and disruption of any service (including OpenAI's services).
- Report findings privately to us before any public disclosure.
- Do not exploit a vulnerability beyond the minimum necessary to demonstrate the issue.
- Comply with all applicable law (including the UK Computer Misuse Act 1990 and equivalents).

This safe-harbour statement is offered as a matter of policy and does not waive the rights or remedies of any third party. It does not authorise testing of OpenAI's, Apple's, or any other third party's systems.

## Out-of-bounds activity

We do not authorise, and we may report or pursue where appropriate, any activity that:

- Compromises the privacy, property, or safety of users.
- Targets infrastructure operated by OpenAI, Apple, or any other third party.
- Conducts denial-of-service or load testing without prior written agreement.
- Engages in social-engineering of Magrathean employees, contractors, or users.

## Contact

Magrathean UK Ltd.
16 Caledonian Court West Street, Watford, England, WD17 1RY
contact@magrathean.uk
