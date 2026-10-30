import Foundation
import InputSourceHelper
import Testing

@testable import gg

@Suite("Input source installation state")
struct InputSourceInstallationTests {
    private let bundleID = "com.kevin.inputmethod.gg"
    private let modeID = "com.kevin.inputmethod.gg.Bopomofo"

    @Test("A non-selectable parent wrapper and one enabled mode are ready")
    func readyStatePasses() {
        let sources = [
            InputSourceInstallSnapshot(
                bundleID: bundleID, inputModeID: nil, isEnabled: true, isSelectCapable: false),
            InputSourceInstallSnapshot(
                bundleID: bundleID, inputModeID: modeID, isEnabled: true, isSelectCapable: true),
        ]

        #expect(
            InputSourceInstallValidator.issues(
                in: sources, bundleID: bundleID, expectedModeIDs: [modeID]).isEmpty)
    }

    @Test("A selectable top-level wrapper is reported because it can crash input source switching")
    func selectableWrapperFails() {
        let sources = [
            InputSourceInstallSnapshot(
                bundleID: bundleID, inputModeID: nil, isEnabled: true, isSelectCapable: true),
            InputSourceInstallSnapshot(
                bundleID: bundleID, inputModeID: modeID, isEnabled: true, isSelectCapable: true),
        ]

        #expect(
            InputSourceInstallValidator.issues(
                in: sources, bundleID: bundleID, expectedModeIDs: [modeID])
                .contains("The top-level input source is still selectable."))
    }

    @Test("A missing or disabled mode is not considered installed")
    func missingOrDisabledModeFails() {
        let missing = InputSourceInstallValidator.issues(
            in: [], bundleID: bundleID, expectedModeIDs: [modeID])
        let disabled = InputSourceInstallValidator.issues(
            in: [InputSourceInstallSnapshot(bundleID: bundleID, inputModeID: modeID, isEnabled: false)],
            bundleID: bundleID,
            expectedModeIDs: [modeID])

        #expect(missing.contains("Input mode is not registered: \(modeID)"))
        #expect(disabled.contains("Input mode is not enabled: \(modeID)"))
    }

    @Test("Duplicate modes are rejected")
    func duplicateModeFails() {
        let sources = [
            InputSourceInstallSnapshot(bundleID: bundleID, inputModeID: modeID, isEnabled: true),
            InputSourceInstallSnapshot(bundleID: bundleID, inputModeID: modeID, isEnabled: true),
        ]

        #expect(
            InputSourceInstallValidator.issues(
                in: sources, bundleID: bundleID, expectedModeIDs: [modeID])
                .contains("Input mode is registered more than once: \(modeID)"))
    }

    @Test("A bundle with no declared modes is rejected")
    func emptyModeListFails() {
        #expect(
            InputSourceInstallValidator.issues(
                in: [], bundleID: bundleID, expectedModeIDs: []).contains(
                    "No input modes are declared in the input method bundle."))
    }

    @Test("HIToolbox plist sync and cleanup work natively without Python")
    func hitoolboxPlistSyncAndCleanup() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-hitoolbox-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let initialDict: [String: Any] = [
            "AppleEnabledInputSources": [
                [
                    "InputSourceKind": "Keyboard Layout",
                    "KeyboardLayout ID": 252,
                    "KeyboardLayout Name": "ABC"
                ],
                [
                    "Bundle ID": bundleID,
                    "InputSourceKind": "Keyboard Input Method"
                ],
                [
                    "Bundle ID": "com.kevin.inputmethod.Anev",
                    "Input Mode": "com.kevin.inputmethod.Anev.Bopomofo",
                    "InputSourceKind": "Input Mode"
                ]
            ]
        ]
        let initialData = try PropertyListSerialization.data(
            fromPropertyList: initialDict, format: .binary, options: 0
        )
        try initialData.write(to: tempURL)

        #expect(
            InputSourceHelper.syncHIToolboxInputSourcesForInstall(
                plistPath: tempURL.path,
                bundleID: bundleID,
                modeIDs: [modeID]
            )
        )

        let syncedData = try Data(contentsOf: tempURL)
        let syncedPlist = try PropertyListSerialization.propertyList(
            from: syncedData, options: [], format: nil
        ) as? [String: Any]
        let enabledAfterInstall = (syncedPlist?["AppleEnabledInputSources"] as? [[String: Any]]) ?? []

        #expect(enabledAfterInstall.count == 2)
        #expect(enabledAfterInstall.contains {
            ($0["Bundle ID"] as? String) == bundleID
                && ($0["Input Mode"] as? String) == modeID
                && ($0["InputSourceKind"] as? String) == "Input Mode"
        })
        #expect(!enabledAfterInstall.contains {
            ($0["InputSourceKind"] as? String) == "Keyboard Input Method"
        })

        #expect(
            InputSourceHelper.cleanupHIToolboxInputSourcesForUninstall(
                plistPath: tempURL.path,
                bundleID: bundleID
            )
        )

        let cleanedData = try Data(contentsOf: tempURL)
        let cleanedPlist = try PropertyListSerialization.propertyList(
            from: cleanedData, options: [], format: nil
        ) as? [String: Any]
        let enabledAfterUninstall = (cleanedPlist?["AppleEnabledInputSources"] as? [[String: Any]]) ?? []
        #expect(enabledAfterUninstall.count == 1)
        #expect((enabledAfterUninstall.first?["KeyboardLayout Name"] as? String) == "ABC")
    }
}
