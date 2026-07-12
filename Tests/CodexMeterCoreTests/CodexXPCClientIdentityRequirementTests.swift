import XCTest
@testable import CodexMeterCore

final class CodexXPCClientIdentityRequirementTests: XCTestCase {
    func testMainAppRequirementMatchesSignedAppIdentity() {
        XCTAssertEqual(
            CodexXPCClientIdentityRequirement.mainAppRequirement,
            #"anchor apple generic and identifier "com.magrathean.CodexexApp" and (certificate leaf[subject.OU] = "NPSQV9WYS5" or entitlement["com.apple.developer.team-identifier"] = "NPSQV9WYS5")"#
        )
    }

    func testDevelopmentBypassDoesNotApplyInReleasePolicy() {
        XCTAssertFalse(
            CodexXPCClientIdentityRequirement.allowsDevelopmentBypass(
                isDebugBuild: false,
                environment: [CodexXPCClientIdentityRequirement.developmentBypassEnvironmentKey: "1"]
            )
        )
    }

    func testDevelopmentBypassRequiresDebugBuildAndExplicitOptIn() {
        XCTAssertTrue(
            CodexXPCClientIdentityRequirement.allowsDevelopmentBypass(
                isDebugBuild: true,
                environment: [CodexXPCClientIdentityRequirement.developmentBypassEnvironmentKey: "1"]
            )
        )
        XCTAssertFalse(
            CodexXPCClientIdentityRequirement.allowsDevelopmentBypass(
                isDebugBuild: true,
                environment: [CodexXPCClientIdentityRequirement.developmentBypassEnvironmentKey: "true"]
            )
        )
    }
}
