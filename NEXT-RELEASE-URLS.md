# Next release: use the magrathean.uk/solutions URLs

Release trigger (1 October 2026). Before or as part of the **next release** of
anything built from this repository, replace the former product-site URLs and
support addresses below. The former domains currently 301 to the new pages, but
those redirects end when the domains lapse (most expire in May 2027). Delete
this file once every reference is updated and released.

| Former | Current |
| --- | --- |
| `https://auditex.hu/<path>` | `https://magrathean.uk/solutions/auditex/<path>` |
| `https://codexex.eu/<path>` | `https://magrathean.uk/solutions/codexex/<path>` |
| `https://nodexapp.eu/<path>` | `https://magrathean.uk/solutions/nodex/<path>` |
| `https://termexapp.eu/<path>` | `https://magrathean.uk/solutions/termex/<path>` |
| `https://teslacam.eu/<path>` | `https://magrathean.uk/solutions/tescam/<path>` |
| `https://teslatlas.eu/<path>` | `https://magrathean.uk/solutions/teslatlas/<path>` (old `/privacy/` and `/terms/` → `/app/privacy/`, `/app/terms/`; donate → `https://magrathean.uk/donate/?product=teslatlas`) |
| `https://magrathean.uk/apps/<slug>/` | `https://magrathean.uk/solutions/<slug>/` |
| Product support e-mail | `contact+<slug>@magrathean.uk` (`auditex`, `codexex`, `nodex`, `termex`, `tescam`, `teslatlas`); `contact+teslacam@` becomes `contact+tescam@` |

Also update the App Store Connect marketing, support and privacy URLs for each
app. Historical records (release-key files, changelogs, archived plans) may keep
their original URLs when the value is part of the record.

## References found in this repository

- `.github/SUPPORT.md:3` — `Product information and the App Store support destination are at [codexex.eu](https://codexex.eu/). For support, use [contact+codexex@magrat`
- `LICENSE:17` — `(https://codexex.eu/terms/), not by this licence.`
- `README.md:10` — `<a href="https://codexex.eu">Website</a> ·`
- `README.md:12` — `<a href="https://codexex.eu/privacy/">Privacy</a>`
- `README.md:40` — `account service. See the [privacy notice](https://codexex.eu/privacy/) for the full`
- `Sources/CodexMeterApp/Support/CodexAppLinks.swift:5` — `static let termsURL = URL(string: "https://codexex.eu/terms/")!`
- `Sources/CodexMeterApp/Support/CodexAppLinks.swift:6` — `static let privacyURL = URL(string: "https://codexex.eu/privacy/")!`
- `Sources/CodexMeteriOS/CodexiOSSettingsView.swift:38` — `static let privacyPolicy = URL(string: "https://codexex.eu/privacy/")!`
- `Sources/CodexMeteriOS/CodexiOSSettingsView.swift:39` — `static let termsOfService = URL(string: "https://codexex.eu/terms/")!`
- `Tests/CodexMeteriOSTests/CodexiOSMatrixSpeedTests.swift:40` — `XCTAssertEqual(CodexiOSLegalLinks.privacyPolicy.absoluteString, "https://codexex.eu/privacy/")`
- `Tests/CodexMeteriOSTests/CodexiOSMatrixSpeedTests.swift:41` — `XCTAssertEqual(CodexiOSLegalLinks.termsOfService.absoluteString, "https://codexex.eu/terms/")`
- `fastlane/metadata/up-6762058457/IOS/en-US/description.txt:11` — `EULA / Terms of Use: https://codexex.eu/terms`
- `fastlane/metadata/up-6762058457/IOS/en-US/description.txt:12` — `Privacy Policy: https://codexex.eu/privacy/`
- `fastlane/metadata/up-6762058457/IOS/en-US/marketing_url.txt:1` — `https://codexex.eu/`
- `fastlane/metadata/up-6762058457/IOS/en-US/support_url.txt:1` — `https://codexex.eu/`
- `fastlane/metadata/up-6762058457/MACOS/en-US/description.txt:11` — `EULA / Terms of Use: https://codexex.eu/terms`
- `fastlane/metadata/up-6762058457/MACOS/en-US/description.txt:12` — `Privacy Policy: https://codexex.eu/privacy/`
- `fastlane/metadata/up-6762058457/MACOS/en-US/marketing_url.txt:1` — `https://codexex.eu/`
- `fastlane/metadata/up-6762058457/MACOS/en-US/support_url.txt:1` — `https://codexex.eu/`
- `fastlane/metadata/up-6762058457/appInfo/en-US.txt:3` — `"privacyPolicyUrl" = "https://codexex.eu/privacy/";`
