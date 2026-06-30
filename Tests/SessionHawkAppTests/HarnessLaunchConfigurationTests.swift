import Foundation
import Testing
@testable import SessionHawkApp

struct HarnessLaunchConfigurationTests {
    @Test
    func defaultsMatchNormalAppLaunch() {
        let configuration = HarnessLaunchConfiguration(environment: [:])

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.shouldStartBridge)
        #expect(configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }

    @Test
    func parsesScenarioFlagsAndAutoExit() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "SESSION_HAWK_HARNESS_SCENARIO": "approvalcard",
                "SESSION_HAWK_HARNESS_PRESENT_OVERLAY": "true",
                "SESSION_HAWK_HARNESS_START_BRIDGE": "no",
                "SESSION_HAWK_HARNESS_BOOT_ANIMATION": "off",
                "SESSION_HAWK_HARNESS_CAPTURE_DELAY_SECONDS": "1.5",
                "SESSION_HAWK_HARNESS_AUTO_EXIT_SECONDS": "2.5",
                "SESSION_HAWK_HARNESS_ARTIFACT_DIR": "/tmp/session-hawk-artifacts",
            ]
        )

        #expect(configuration.scenario == .approvalCard)
        #expect(configuration.presentOverlay)
        #expect(!configuration.shouldStartBridge)
        #expect(!configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == 1.5)
        #expect(configuration.autoExitAfter == 2.5)
        #expect(configuration.artifactDirectoryURL?.path == "/tmp/session-hawk-artifacts")
    }

    @Test
    func ignoresInvalidInputs() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "SESSION_HAWK_HARNESS_SCENARIO": "missing",
                "SESSION_HAWK_HARNESS_PRESENT_OVERLAY": "unexpected",
                "SESSION_HAWK_HARNESS_CAPTURE_DELAY_SECONDS": "0",
                "SESSION_HAWK_HARNESS_AUTO_EXIT_SECONDS": "-1",
                "SESSION_HAWK_HARNESS_ARTIFACT_DIR": "   ",
            ]
        )

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }
}
