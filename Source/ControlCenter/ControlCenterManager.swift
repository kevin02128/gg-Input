// Copyright © 2026 wtf. All rights reserved.
// ControlCenterManager.swift — gg 控制台核心管理引擎（狀態監控、模型開關、安裝與解除安裝）

import Foundation
import Cocoa
import Combine
import Carbon

public enum IMEProcessState: Equatable {
    case running(pid: Int)
    case stopped
    case notInstalled

    public var displayText: String {
        switch self {
        case .running(let pid):
            return "運作中 (PID: \(pid))"
        case .stopped:
            return "已停止 (已安裝但未運行)"
        case .notInstalled:
            return "尚未安裝至系統"
        }
    }

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

// MARK: - Carbon TIS InputSource Helper

@MainActor
public class SystemInputSourceHelper {
    public static func allInstalledInputSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    public static func registerInputSource(at url: URL) -> Bool {
        let status = TISRegisterInputSource(url as CFURL)
        return status == noErr
    }

    public static func enableAllInputModes(for bundleID: String) -> Bool {
        var enabledAny = false
        for source in allInstalledInputSources() {
            guard let bundleIDPtr = TISGetInputSourceProperty(source, kTISPropertyBundleID),
                  let _ = TISGetInputSourceProperty(source, kTISPropertyInputModeID) else {
                continue
            }
            let bid = Unmanaged<CFString>.fromOpaque(bundleIDPtr).takeUnretainedValue() as String
            if bid == bundleID {
                let status = TISEnableInputSource(source)
                if status == noErr {
                    enabledAny = true
                }
            }
        }
        return enabledAny
    }
}

@MainActor
public class ControlCenterManager: ObservableObject {
    public static let shared = ControlCenterManager()

    // MARK: - Published Properties

    @Published public var imeState: IMEProcessState = .stopped
    @Published public var installedVersion: String = "未檢測到"
    @Published public var imeAppPath: String = ""

    // 安裝與維護狀態
    @Published public var isInstalling: Bool = false
    @Published public var installProgressMessage: String = ""
    @Published public var isBusy: Bool = false
    @Published public var maintenanceMessage: String = ""

    // Kyon 神經引擎開關
    @Published public var wtfContextCorrection: Bool = true {
        didSet { savePreference(key: "WTFContextCorrectionEnabled", value: wtfContextCorrection) }
    }

    // MARK: - 神經模型即時遙測
    @Published public var neuralModelName: String = "Kyon"
    @Published public var neuralModelLoaded: Bool = false
    @Published public var neuralTotalInferences: Int = 0
    @Published public var neuralLastLatencyMs: Double = 0.0
    @Published public var neuralLastSummary: String = "尚未觸發神經推論"
    @Published public var neuralModelSizeString: String = "整句 N-Best 審查架構"
    @Published public var neuralHardwareEngine: String = "Apple Neural Engine (ANE)"

    // MARK: - Constants & Paths

    public let targetAppBundle = "gg.app"
    public let suiteName = "com.wtf.inputmethod.gg"

    public var targetAppURL: URL {
        let inputMethodsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods")
        return inputMethodsDir.appendingPathComponent(targetAppBundle)
    }

    public var userSupportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/gg")
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private var timer: Timer?

    // MARK: - Initialization

    public init() {
        let appURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/gg.app")
        self.imeAppPath = appURL.path

        loadPreferences()
        refreshStatus()

        self.timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Preferences Management

    private func loadPreferences() {
        let d = defaults
        if d.object(forKey: "WTFContextCorrectionEnabled") != nil {
            self.wtfContextCorrection = d.bool(forKey: "WTFContextCorrectionEnabled")
        }
    }

    private func savePreference(key: String, value: Any) {
        defaults.set(value, forKey: key)
        CFPreferencesAppSynchronize(suiteName as CFString)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.wtf.inputmethod.gg.preferencesChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    // MARK: - Status Checking (Non-blocking Background Execution)

    public func refreshStatus() {
        let appURL = targetAppURL
        let suite = suiteName

        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let appExists = fileManager.fileExists(atPath: appURL.path)

            if !appExists {
                await MainActor.run {
                    self.imeState = .notInstalled
                    self.installedVersion = "尚未安裝"
                    self.neuralModelLoaded = false
                }
                return
            }

            var versionText = "已安裝 (版本未知)"
            let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
            if let data = try? Data(contentsOf: infoPlist),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                let shortVer = plist["CFBundleShortVersionString"] as? String ?? ""
                let ver = plist["CFBundleVersion"] as? String ?? ""
                versionText = "\(shortVer) (build \(ver))"
            }

            let pid = Self.checkProcessPIDBackground()

            CFPreferencesAppSynchronize(suite as CFString)
            let d = UserDefaults(suiteName: suite) ?? .standard
            let modelName = d.string(forKey: "NeuralModelName") ?? "Kyon"
            let totalInf = d.integer(forKey: "NeuralTotalInferences")
            let lastLat = d.double(forKey: "NeuralLastLatencyMs")
            let summary = d.string(forKey: "NeuralLastSummary") ?? "待命中"
            let sizeStr = d.string(forKey: "NeuralModelSizeString") ?? "整句 N-Best 審查架構"
            let hwStr = d.string(forKey: "NeuralHardwareEngine") ?? "Apple Neural Engine (ANE)"
            let hasLoadedKey = d.object(forKey: "NeuralIsModelLoaded") != nil
            let isLoadedVal = d.bool(forKey: "NeuralIsModelLoaded")
            let finalVersion = versionText

            await MainActor.run {
                self.installedVersion = finalVersion
                if let pid = pid {
                    self.imeState = .running(pid: pid)
                } else {
                    self.imeState = .stopped
                }
                self.neuralModelName = modelName.isEmpty ? "Kyon" : modelName
                self.neuralTotalInferences = totalInf
                self.neuralLastLatencyMs = lastLat
                self.neuralLastSummary = summary.isEmpty ? "待命中" : summary
                self.neuralModelSizeString = sizeStr
                self.neuralHardwareEngine = hwStr
                if hasLoadedKey {
                    self.neuralModelLoaded = isLoadedVal
                } else {
                    self.neuralModelLoaded = (pid != nil)
                }
            }
        }
    }

    nonisolated private static func checkProcessPIDBackground() -> Int? {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "Contents/MacOS/gg"]

        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let firstLine = output.components(separatedBy: "\n").first,
           let pid = Int(firstLine) {
            return pid
        }
        return nil
    }

    // MARK: - Install or Upgrade IME

    public func installOrUpgradeIME() {
        isInstalling = true
        installProgressMessage = "正在準備安裝 gg 輸入法..."

        let destAppURL = targetAppURL
        let bundleID = suiteName

        Task.detached {
            let fm = FileManager.default

            func isValidIMEBundle(_ url: URL) -> Bool {
                if url.path.contains("Index.noindex") { return false }
                let execURL = url.appendingPathComponent("Contents/MacOS/gg")
                guard fm.fileExists(atPath: execURL.path) else { return false }
                if let attrs = try? fm.attributesOfItem(atPath: execURL.path),
                   let size = attrs[.size] as? Int64, size > 1024 {
                    return true
                }
                return false
            }

            var sourceURL: URL?

            if let resourceURL = Bundle.main.resourceURL {
                let candidate = resourceURL.appendingPathComponent("gg.app")
                if isValidIMEBundle(candidate) {
                    sourceURL = candidate
                }
            }

            if sourceURL == nil {
                let appBundleURL = Bundle.main.bundleURL
                let siblingCandidate = appBundleURL.deletingLastPathComponent().appendingPathComponent("gg.app")
                if isValidIMEBundle(siblingCandidate) {
                    sourceURL = siblingCandidate
                }
            }

            if sourceURL == nil {
                let derivedPattern = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Developer/Xcode/DerivedData")
                var newestDate: Date = .distantPast
                if let enumerator = fm.enumerator(at: derivedPattern, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if fileURL.lastPathComponent == "gg.app" && isValidIMEBundle(fileURL) {
                            let execPath = fileURL.appendingPathComponent("Contents/MacOS/gg").path
                            let modDate = (try? fm.attributesOfItem(atPath: execPath)[.modificationDate] as? Date) ?? .distantPast
                            if modDate >= newestDate {
                                newestDate = modDate
                                sourceURL = fileURL
                            }
                        }
                    }
                }
            }

            guard let validSource = sourceURL else {
                await MainActor.run {
                    self.isInstalling = false
                    self.installProgressMessage = "找不到 gg.app 安裝包，請先在 Xcode 中建置 gg Target。"
                }
                return
            }

            await MainActor.run {
                self.installProgressMessage = "正在替換與啟動輸入法..."
            }

            let killTask = Process()
            killTask.launchPath = "/usr/bin/pkill"
            killTask.arguments = ["-9", "-f", "Contents/MacOS/gg"]
            try? killTask.run()
            killTask.waitUntilExit()

            try? await Task.sleep(nanoseconds: 200_000_000)

            let destFolder = destAppURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: destFolder.path) {
                try? fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
            }

            if fm.fileExists(atPath: destAppURL.path) {
                try? fm.removeItem(at: destAppURL)
            }
            do {
                try fm.copyItem(at: validSource, to: destAppURL)
            } catch {
                await MainActor.run {
                    self.isInstalling = false
                    self.installProgressMessage = "複製檔案失敗：\(error.localizedDescription)"
                }
                return
            }

            let xattrTask = Process()
            xattrTask.launchPath = "/usr/bin/xattr"
            xattrTask.arguments = ["-cr", destAppURL.path]
            try? xattrTask.run()
            xattrTask.waitUntilExit()

            let signTask = Process()
            signTask.launchPath = "/usr/bin/codesign"
            signTask.arguments = ["--force", "--deep", "--sign", "-", destAppURL.path]
            try? signTask.run()
            signTask.waitUntilExit()

            let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
            if fm.fileExists(atPath: lsregisterPath) {
                let lsTask = Process()
                lsTask.launchPath = lsregisterPath
                lsTask.arguments = ["-f", "-R", "-trusted", destAppURL.path]
                try? lsTask.run()
                lsTask.waitUntilExit()
            }

            await MainActor.run {
                _ = SystemInputSourceHelper.registerInputSource(at: destAppURL)
                _ = SystemInputSourceHelper.enableAllInputModes(for: bundleID)
            }

            let openTask = Process()
            openTask.launchPath = "/usr/bin/open"
            openTask.arguments = ["-a", destAppURL.path]
            try? openTask.run()
            openTask.waitUntilExit()

            try? await Task.sleep(nanoseconds: 800_000_000)

            await MainActor.run {
                self.refreshStatus()
                self.isInstalling = false
                self.installProgressMessage = "安裝完成"
            }
        }
    }

    // MARK: - Restart IME

    public func restartIME() {
        isBusy = true
        maintenanceMessage = "正在重啟 gg 輸入法..."

        let appPath = targetAppURL.path

        Task.detached {
            let killTask = Process()
            killTask.launchPath = "/usr/bin/pkill"
            killTask.arguments = ["-9", "-f", "Contents/MacOS/gg"]
            try? killTask.run()
            killTask.waitUntilExit()

            try? await Task.sleep(nanoseconds: 300_000_000)

            let openTask = Process()
            openTask.launchPath = "/usr/bin/open"
            openTask.arguments = ["-a", appPath]
            try? openTask.run()
            openTask.waitUntilExit()

            try? await Task.sleep(nanoseconds: 600_000_000)

            await MainActor.run {
                self.refreshStatus()
                self.isBusy = false
                self.maintenanceMessage = "已成功重啟輸入法程序"
            }
        }
    }

    // MARK: - Uninstaller

    public func uninstallIME(deleteUserData: Bool) {
        isBusy = true
        maintenanceMessage = "正在解除安裝..."

        let appURL = targetAppURL
        let supportDir = userSupportDir
        let suite = suiteName

        Task.detached {
            let killTask = Process()
            killTask.launchPath = "/usr/bin/killall"
            killTask.arguments = ["-9", "gg"]
            try? killTask.run()
            killTask.waitUntilExit()

            let pkillTask = Process()
            pkillTask.launchPath = "/usr/bin/pkill"
            pkillTask.arguments = ["-9", "-f", "gg.app"]
            try? pkillTask.run()
            pkillTask.waitUntilExit()

            let fm = FileManager.default
            if fm.fileExists(atPath: appURL.path) {
                try? fm.removeItem(at: appURL)
            }

            if deleteUserData {
                if fm.fileExists(atPath: supportDir.path) {
                    try? fm.removeItem(at: supportDir)
                }
                let defaultsTask = Process()
                defaultsTask.launchPath = "/usr/bin/defaults"
                defaultsTask.arguments = ["delete", suite]
                try? defaultsTask.run()
                defaultsTask.waitUntilExit()
            }

            try? await Task.sleep(nanoseconds: 600_000_000)

            await MainActor.run {
                self.refreshStatus()
                self.isBusy = false
                self.maintenanceMessage = "gg 輸入法已移除。"
            }
        }
    }

    public func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
