// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import Cocoa
import Carbon
import InputMethodKit
import InputSourceHelper

struct InputSourceInstallSnapshot: Equatable {
    let bundleID: String?
    let inputModeID: String?
    let isEnabled: Bool
    let isSelectCapable: Bool

    init(bundleID: String?, inputModeID: String?, isEnabled: Bool, isSelectCapable: Bool = false) {
        self.bundleID = bundleID
        self.inputModeID = inputModeID
        self.isEnabled = isEnabled
        self.isSelectCapable = isSelectCapable
    }
}

enum InputSourceInstallValidator {
    static func issues(
        in sources: [InputSourceInstallSnapshot], bundleID: String, expectedModeIDs: Set<String>
    ) -> [String] {
        guard !expectedModeIDs.isEmpty else {
            return ["No input modes are declared in the input method bundle."]
        }

        let bundledSources = sources.filter { $0.bundleID == bundleID }
        var issues: [String] = []
        if bundledSources.contains(where: { $0.inputModeID == nil && $0.isSelectCapable && $0.isEnabled }) {
            issues.append("The top-level input source is still selectable.")
        }

        for modeID in expectedModeIDs.sorted() {
            let matchingModes = bundledSources.filter { $0.inputModeID == modeID }
            if matchingModes.isEmpty {
                issues.append("Input mode is not registered: \(modeID)")
            } else if matchingModes.count > 1 {
                issues.append("Input mode is registered more than once: \(modeID)")
            } else if !matchingModes[0].isEnabled {
                issues.append("Input mode is not enabled: \(modeID)")
            }
        }
        return issues
    }
}

private func declaredInputModeIDs(from infoDictionary: [String: Any]) -> Set<String> {
    guard
        let componentModes = infoDictionary["ComponentInputModeDict"] as? [String: Any],
        let modeList = componentModes["tsInputModeListKey"] as? [String: Any]
    else {
        return []
    }
    return Set(modeList.keys)
}

private func inputSourceInstallSnapshots() -> [InputSourceInstallSnapshot]? {
    guard let sources = InputSourceHelper.snapshots() else {
        return nil
    }
    return sources.map {
        InputSourceInstallSnapshot(
            bundleID: $0.bundleID,
            inputModeID: $0.inputModeID,
            isEnabled: $0.isEnabled,
            isSelectCapable: $0.isSelectCapable
        )
    }
}

private func pruneStaleRegistrations(bundleID: String, targetURL: URL) {
    let urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
    let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
    guard FileManager.default.isExecutableFile(atPath: lsregisterPath) else { return }

    let targetStandardized = targetURL.standardizedFileURL.path
    for url in urls {
        let path = url.standardizedFileURL.path
        if path != targetStandardized {
            NSLog("Pruning stale input method registration at %@", path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: lsregisterPath)
            process.arguments = ["-u", path]
            try? process.run()
            process.waitUntilExit()
        }
    }
}

private func install() -> Int32 {
    guard let bundleID = Bundle.main.bundleIdentifier else {
        NSLog("gg install failed: bundle identifier is missing.")
        return -1
    }

    if Bundle.main.bundleURL.path.contains("/DerivedData/") {
        NSLog("Refusing to register input source from DerivedData development build.")
        return 0
    }

    pruneStaleRegistrations(bundleID: bundleID, targetURL: Bundle.main.bundleURL)

    let expectedModeIDs = declaredInputModeIDs(from: Bundle.main.infoDictionary ?? [:])
    guard !expectedModeIDs.isEmpty else {
        NSLog("gg install failed: no input modes are declared in Info.plist.")
        return -1
    }

    guard var sources = inputSourceInstallSnapshots() else {
        NSLog("gg install failed: macOS could not enumerate text input sources.")
        return -1
    }

    let hasEveryDeclaredMode = expectedModeIDs.allSatisfy { modeID in
        sources.contains { $0.bundleID == bundleID && $0.inputModeID == modeID }
    }
    if !hasEveryDeclaredMode {
        NSLog("Registering input source %@ at %@", bundleID, Bundle.main.bundleURL.path)
        guard InputSourceHelper.registerInputSource(at: Bundle.main.bundleURL) else {
            NSLog("gg install failed: TISRegisterInputSource returned an error.")
            return -1
        }
        guard let refreshedSources = inputSourceInstallSnapshots() else {
            NSLog("gg install failed: macOS could not refresh text input sources after registration.")
            return -1
        }
        sources = refreshedSources
    }

    guard sources.contains(where: { $0.bundleID == bundleID }) else {
        NSLog("gg install failed: the input method bundle was not registered with macOS.")
        return -1
    }

    _ = InputSourceHelper.disableInputSourcesWithoutMode(for: bundleID)

    guard InputSourceHelper.enableAllInputMode(for: bundleID) else {
        NSLog("gg install failed: one or more input modes could not be enabled.")
        return -1
    }

    guard let verifiedSources = inputSourceInstallSnapshots() else {
        NSLog("gg install failed: macOS could not verify the registered input sources.")
        return -1
    }
    let issues = InputSourceInstallValidator.issues(
        in: verifiedSources, bundleID: bundleID, expectedModeIDs: expectedModeIDs)
    guard issues.isEmpty else {
        for issue in issues {
            NSLog("gg install verification failed: %@", issue)
        }
        return -1
    }

    let hitoolboxPath = CommandLine.arguments.count > 2
        ? CommandLine.arguments[2]
        : (NSHomeDirectory() + "/Library/Preferences/com.apple.HIToolbox.plist")
    _ = InputSourceHelper.syncHIToolboxInputSourcesForInstall(
        plistPath: hitoolboxPath,
        bundleID: bundleID,
        modeIDs: expectedModeIDs
    )

    NSLog("gg input source registration verified for %@.", bundleID)
    return 0
}

private func uninstallInputSource() -> Int32 {
    guard let bundleID = Bundle.main.bundleIdentifier else {
        NSLog("gg uninstall failed: bundle identifier is missing.")
        return -1
    }
    guard InputSourceHelper.selectInputSource(withID: "com.apple.keylayout.ABC")
            || InputSourceHelper.selectInputSource(withID: "com.apple.keylayout.US")
    else {
        NSLog("gg uninstall failed: could not switch to an English keyboard layout.")
        return -1
    }
    guard InputSourceHelper.disableAllInputSources(for: bundleID) else {
        NSLog("gg uninstall failed: one or more gg input sources could not be disabled.")
        return -1
    }
    let hitoolboxPath = CommandLine.arguments.count > 2
        ? CommandLine.arguments[2]
        : (NSHomeDirectory() + "/Library/Preferences/com.apple.HIToolbox.plist")
    _ = InputSourceHelper.cleanupHIToolboxInputSourcesForUninstall(
        plistPath: hitoolboxPath,
        bundleID: bundleID
    )
    return 0
}

guard let connectionName = (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String), !connectionName.isEmpty else {
    NSLog("%@", "Fatal error: InputMethodConnectionName key not defined in Info.plist.")
    exit(-1)
}

if CommandLine.arguments.count > 1 {
    switch CommandLine.arguments[1] {
    case "install":
        let exitCode = install()
        exit(exitCode)
    case "uninstall":
        let exitCode = uninstallInputSource()
        exit(exitCode)
    default:
        break
    }
}

guard let mainNibName = Bundle.main.infoDictionary?["NSMainNibFile"] as? String else {
    NSLog("%@", "Fatal error: NSMainNibFile key not defined in Info.plist.")
    exit(-1)
}

let loaded = Bundle.main.loadNibNamed(mainNibName, owner: NSApp, topLevelObjects: nil)
if !loaded {
    NSLog("%@", "Fatal error: Cannot load \(mainNibName).")
    exit(-1)
}

guard let bundleID = Bundle.main.bundleIdentifier, let server = IMKServer(name: connectionName, bundleIdentifier: bundleID) else {
    NSLog("%@", "Fatal error: Cannot initialize input method server with connection \(connectionName).")
    exit(-1)
}

Preferences.populateDefaults()
NSApp.run()
