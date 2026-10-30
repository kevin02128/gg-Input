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

public class InputSourceHelper: NSObject {

    public struct Snapshot: Equatable {
        public let inputSourceID: String?
        public let bundleID: String?
        public let inputModeID: String?
        public let isEnabled: Bool
        public let isSelectCapable: Bool

        public init(
            inputSourceID: String?,
            bundleID: String?,
            inputModeID: String?,
            isEnabled: Bool,
            isSelectCapable: Bool = false
        ) {
            self.inputSourceID = inputSourceID
            self.bundleID = bundleID
            self.inputModeID = inputModeID
            self.isEnabled = isEnabled
            self.isSelectCapable = isSelectCapable
        }
    }

    @available(*, unavailable)
    public override init() {
        super.init()
    }

    public static func allInstalledInputSources() -> [TISInputSource] {
        inputSourceList() ?? []
    }

    private static func inputSourceList() -> [TISInputSource]? {
        guard let unmanagedSources = TISCreateInputSourceList(nil, true) else {
            return nil
        }
        return unmanagedSources.takeRetainedValue() as? [TISInputSource]
    }

    private static func stringProperty(_ key: CFString, of source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return String(Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue())
    }

    private static func booleanProperty(_ key: CFString, of source: TISInputSource) -> Bool {
        guard let property = TISGetInputSourceProperty(source, key),
              CFGetTypeID(Unmanaged<CFTypeRef>.fromOpaque(property).takeUnretainedValue())
                == CFBooleanGetTypeID()
        else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(property).takeUnretainedValue())
    }

    private static func enabledProperty(of source: TISInputSource) -> Bool {
        return booleanProperty(kTISPropertyInputSourceIsEnabled, of: source)
    }

    public static func snapshots() -> [Snapshot]? {
        guard let sources = inputSourceList() else {
            return nil
        }
        return sources.map { source in
            Snapshot(
                inputSourceID: stringProperty(kTISPropertyInputSourceID, of: source),
                bundleID: stringProperty(kTISPropertyBundleID, of: source),
                inputModeID: stringProperty(kTISPropertyInputModeID, of: source),
                isEnabled: enabledProperty(of: source),
                isSelectCapable: booleanProperty(kTISPropertyInputSourceIsSelectCapable, of: source))
        }
    }

    @objc(inputSourceForProperty:stringValue:)
    public static func inputSource(for propertyKey: CFString, stringValue: String) -> TISInputSource? {
        let stringID = CFStringGetTypeID()
        guard let sources = inputSourceList() else {
            return nil
        }
        for source in sources {
            if let propertyPtr = TISGetInputSourceProperty(source, propertyKey) {
                let property = Unmanaged<CFTypeRef>.fromOpaque(propertyPtr).takeUnretainedValue()
                let typeID = CFGetTypeID(property)
                if typeID != stringID {
                    continue
                }
                if stringValue == property as? String {
                    return source
                }
            }
        }
        return nil
    }

    @objc(inputSourceForInputSourceID:)
    public static func inputSource(for sourceID: String) -> TISInputSource? {
        inputSource(for: kTISPropertyInputSourceID, stringValue: sourceID)
    }

    public static func selectInputSource(withID sourceID: String) -> Bool {
        guard let inputSource = inputSource(for: sourceID) else {
            return false
        }
        let status = TISSelectInputSource(inputSource)
        return status == noErr
    }

    @objc(inputSourceEnabled:)
    public static func inputSourceEnabled(for source: TISInputSource) -> Bool {
        enabledProperty(of: source)
    }

    @objc(enableInputSource:)
    public static func enable(inputSource: TISInputSource) -> Bool {
        let status = TISEnableInputSource(inputSource)
        return status == noErr
    }

    @objc(enableAllInputModesForInputSourceBundleID:)
    public static func enableAllInputMode(for inputSourceBundleD: String) -> Bool {
        var enabled = false
        guard let sources = inputSourceList() else {
            return false
        }
        for source in sources {
            guard stringProperty(kTISPropertyBundleID, of: source) == inputSourceBundleD,
                  stringProperty(kTISPropertyInputModeID, of: source) != nil else {
                continue
            }
            if !enable(inputSource: source) {
                return false
            }
            enabled = true
        }

        return enabled
    }

    @objc(enableInputMode:forInputSourceBundleID:)
    public static func enable(inputMode modeID: String, for bundleID: String) -> Bool {
        for source in allInstalledInputSources() {
            guard let bundleIDPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID),
                  let modePtr = TISGetInputSourceProperty(source, kTISPropertyInputModeID) else {
                continue
            }
            let inputsSourceBundleID = Unmanaged<CFString>.fromOpaque(bundleIDPtr).takeUnretainedValue()
            let inputsSourceModeID = Unmanaged<CFString>.fromOpaque(modePtr).takeUnretainedValue()
            if modeID == String(inputsSourceModeID) && bundleID == String(inputsSourceBundleID) {
                let enabled = enable(inputSource: source)
                print("Attempt to enable input source of mode: \(modeID), bundle ID: \(bundleID), result: \(enabled)")
                return enabled
            }

        }
        print("Failed to find any matching input source of mode: \(modeID), bundle ID: \(bundleID)")
        return false

    }

    @objc(disableInputSource:)
    public static func disable(inputSource: TISInputSource) -> Bool {
        let status = TISDisableInputSource(inputSource)
        return status == noErr
    }

    public static func disableInputSourcesWithoutMode(for bundleID: String) -> Bool {
        guard let sources = inputSourceList() else {
            return false
        }
        for source in sources where
            stringProperty(kTISPropertyBundleID, of: source) == bundleID
                && stringProperty(kTISPropertyInputModeID, of: source) == nil
                && (stringProperty(kTISPropertyInputSourceType, of: source) == "TISTypeKeyboardInputMethodWithoutModes" || booleanProperty(kTISPropertyInputSourceIsSelectCapable, of: source))
                && inputSourceEnabled(for: source)
        {
            guard disable(inputSource: source) else {
                return false
            }
        }
        return true
    }

    public static func disableAllInputSources(for bundleID: String) -> Bool {
        guard let sources = inputSourceList() else {
            return false
        }
        var found = false
        for source in sources where stringProperty(kTISPropertyBundleID, of: source) == bundleID {
            found = true
            if inputSourceEnabled(for: source) && !disable(inputSource: source) {
                return false
            }
        }
        return found
    }

    @objc(registerInputSource:)
    public static func registerInputSource(at url: URL) -> Bool {
        let status = TISRegisterInputSource(url as CFURL)
        return status == noErr
    }

    private static let hitoolboxSourceKeys = [
        "AppleEnabledInputSources",
        "AppleDefaultAsciiInputSource",
        "AppleCurrentAsciiInputSource",
        "AppleSelectedInputSources",
        "AppleInputSourceHistory"
    ]

    private static let legacyBundleIDs: Set<String> = [
        "com.wtf.inputmethod.gg",
        "com.kevin.inputmethod.Anev"
    ]

    public static func syncHIToolboxInputSourcesForInstall(
        plistPath: String,
        bundleID: String,
        modeIDs: Set<String>
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            return true
        }
        let url = URL(fileURLWithPath: plistPath)
        guard let data = try? Data(contentsOf: url) else {
            return false
        }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let rawPlist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: &format
        ), var dict = rawPlist as? [String: Any] else {
            return false
        }

        var dirty = false
        for key in hitoolboxSourceKeys {
            if let oldList = dict[key] as? [Any] {
                var newList: [Any] = []
                var seen = Set<String>()
                for item in oldList {
                    if let entry = item as? [String: Any] {
                        let bid = entry["Bundle ID"] as? String
                        let kind = entry["InputSourceKind"] as? String
                        let mode = entry["Input Mode"] as? String
                        if let bid = bid, legacyBundleIDs.contains(bid) {
                            continue
                        }
                        if bid == bundleID && kind == "Keyboard Input Method" {
                            continue
                        }
                        let layoutName = entry["KeyboardLayout Name"] as? String ?? ""
                        let layoutID = (entry["KeyboardLayout ID"] as? NSNumber)?.stringValue ?? ""
                        let sig = "\(bid ?? "")|\(kind ?? "")|\(mode ?? "")|\(layoutName)|\(layoutID)"
                        if seen.contains(sig) {
                            continue
                        }
                        seen.insert(sig)
                    }
                    newList.append(item)
                }
                if newList.count != oldList.count {
                    dict[key] = newList
                    dirty = true
                }
            } else if let oldDict = dict[key] as? [String: Any] {
                let bid = oldDict["Bundle ID"] as? String
                let kind = oldDict["InputSourceKind"] as? String
                if (bid != nil && legacyBundleIDs.contains(bid!))
                    || (bid == bundleID && kind == "Keyboard Input Method")
                {
                    dict.removeValue(forKey: key)
                    dirty = true
                }
            }
        }

        var enabledSources = (dict["AppleEnabledInputSources"] as? [Any]) ?? []
        for modeID in modeIDs.sorted() {
            let hasMode = enabledSources.contains { item in
                guard let entry = item as? [String: Any] else { return false }
                return (entry["Bundle ID"] as? String) == bundleID
                    && (entry["Input Mode"] as? String) == modeID
            }
            if !hasMode {
                let newEntry: [String: Any] = [
                    "Bundle ID": bundleID,
                    "Input Mode": modeID,
                    "InputSourceKind": "Input Mode"
                ]
                enabledSources.append(newEntry)
                dirty = true
            }
        }

        if dirty {
            dict["AppleEnabledInputSources"] = enabledSources
            guard let outData = try? PropertyListSerialization.data(
                fromPropertyList: dict, format: format, options: 0
            ) else {
                return false
            }
            do {
                try outData.write(to: url, options: .atomic)
            } catch {
                return false
            }
        }
        return true
    }

    public static func cleanupHIToolboxInputSourcesForUninstall(
        plistPath: String,
        bundleID: String
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            return true
        }
        let url = URL(fileURLWithPath: plistPath)
        guard let data = try? Data(contentsOf: url) else {
            return false
        }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let rawPlist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: &format
        ), var dict = rawPlist as? [String: Any] else {
            return false
        }

        let targets = legacyBundleIDs.union([bundleID])
        var dirty = false
        for key in hitoolboxSourceKeys {
            if let oldList = dict[key] as? [Any] {
                let newList = oldList.filter { item in
                    guard let entry = item as? [String: Any],
                          let bid = entry["Bundle ID"] as? String else {
                        return true
                    }
                    return !targets.contains(bid)
                }
                if newList.count != oldList.count {
                    dict[key] = newList
                    dirty = true
                }
            } else if let oldDict = dict[key] as? [String: Any],
                      let bid = oldDict["Bundle ID"] as? String,
                      targets.contains(bid) {
                dict.removeValue(forKey: key)
                dirty = true
            }
        }

        if dirty {
            guard let outData = try? PropertyListSerialization.data(
                fromPropertyList: dict, format: format, options: 0
            ) else {
                return false
            }
            do {
                try outData.write(to: url, options: .atomic)
            } catch {
                return false
            }
        }
        return true
    }

}

