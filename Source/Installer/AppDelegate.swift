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
import InputSourceHelper

private let kTargetBin = "gg"
private let kTargetType = "app"
private let kTargetBundle = "gg.app"
private let kDestinationPartial = "~/Library/Input Methods/"
private let kTargetPartialPath = "~/Library/Input Methods/gg.app"
private let kTargetFullBinPartialPath = "~/Library/Input Methods/gg.app/Contents/MacOS/gg"

private let kTranslocationRemovalTickInterval: TimeInterval = 0.5
private let kTranslocationRemovalDeadline: TimeInterval = 60.0

@NSApplicationMain
@objc(AppDelegate)
class AppDelegate: NSWindowController, NSApplicationDelegate {
    @IBOutlet weak private var actionButton: NSButton!
    @IBOutlet weak private var cancelButton: NSButton!
    @IBOutlet private var textView: NSTextView!
    @IBOutlet weak private var progressSheet: NSWindow!
    @IBOutlet weak private var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var welcomeText: NSTextField!
    @IBOutlet weak var agreeText: NSTextField!
    
    private var archiveUtil: ArchiveUtil?
    private var installingVersion = ""
    private var upgrading = false
    private var translocationRemovalStartTime: Date?
    private var currentVersionNumber: Int = 0

    private var installed = false
    private var openKeyboardSettingsButton: NSButton?
    private var openSecuritySettingsButton: NSButton?

    func runAlertPanel(title: String, message: String, buttonTitle: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: buttonTitle)
        alert.runModal()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let installingVersion = Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as? String,
              let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }
        self.installingVersion = installingVersion
        self.archiveUtil = ArchiveUtil(appName: kTargetBin, targetAppBundleName: kTargetBundle)
        _ = archiveUtil?.validateIfNotarizedArchiveExists()

        cancelButton.nextKeyView = actionButton
        actionButton.nextKeyView = cancelButton
        if let cell = actionButton.cell as? NSButtonCell {
            window?.defaultButtonCell = cell
        }

        var attrStr = NSAttributedString()
        if let rtfPath = Bundle.main.url(forResource: "License", withExtension: "rtf"),
           let rtfData = try? Data(contentsOf: rtfPath),
           let rtf = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            attrStr = rtf
        }

        let mutableAttrStr = NSMutableAttributedString(attributedString: attrStr)
        mutableAttrStr.addAttribute(.foregroundColor, value: NSColor.controlTextColor, range: NSMakeRange(0, mutableAttrStr.length))
        textView.textStorage?.setAttributedString(mutableAttrStr)
        textView.setSelectedRange(NSMakeRange(0, 0))
        window?.title = String(format: NSLocalizedString("%@ (for version %@, r%@)", comment: ""), window?.title ?? "", versionString, installingVersion)

        if FileManager.default.fileExists(atPath: (kTargetPartialPath as NSString).expandingTildeInPath) {
            let currentBundle = Bundle(path: (kTargetPartialPath as NSString).expandingTildeInPath)
            let shortVersion = currentBundle?.infoDictionary?["CFBundleShortVersionString"] as? String
            let currentVersion = currentBundle?.infoDictionary?[kCFBundleVersionKey as String] as? String
            currentVersionNumber = (currentVersion as NSString?)?.integerValue ?? 0
            if shortVersion != nil, let currentVersion = currentVersion, currentVersion.compare(installingVersion, options: .numeric) == .orderedAscending {
                upgrading = true
            }
        }

        if upgrading {
            actionButton.title = NSLocalizedString("Agree and Upgrade", comment: "")
        }

        window?.center()
        window?.orderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func agreeAndInstallAction(_ sender: AnyObject) {
        if !installed {
            // user agreed to terms for install
            cancelButton.isEnabled = false
            actionButton.isEnabled = false
            removeThenInstallInputMethod()
        } else {
            // installation was successful, user clicked the "Close Installer" button
            endAppWithDelay()
        }
    }

    @objc func timerTick(_ timer: Timer) {
        let elapsed = Date().timeIntervalSince(translocationRemovalStartTime ?? Date())
        if elapsed >= kTranslocationRemovalDeadline {
            timer.invalidate()
            window?.endSheet(progressSheet, returnCode: .cancel)
        } else if appBundleTranslocatedToARandomizedPath(kTargetPartialPath) == false {
            progressIndicator.doubleValue = 1.0
            timer.invalidate()
            window?.endSheet(progressSheet, returnCode: .continue)
        }
    }

    func removeThenInstallInputMethod() {
        if FileManager.default.fileExists(atPath: (kTargetPartialPath as NSString).expandingTildeInPath) == false {
            self.installInputMethod(previousExists: false, previousVersionNotFullyDeactivatedWarning: false)
            return
        }

        let shouldWaitForTranslocationRemoval = appBundleTranslocatedToARandomizedPath(kTargetPartialPath) && (window?.responds(to: #selector(NSWindow.beginSheet(_:completionHandler:))) ?? false)

        let fullDir = (kDestinationPartial as NSString).expandingTildeInPath
        let targetURL = NSURL.fileURL(withPath: fullDir).appendingPathComponent(kTargetBundle)

        // 1. Terminate running instances first so files are not locked
        let killTask = Process()
        killTask.launchPath = "/usr/bin/killall"
        killTask.arguments = ["-9", kTargetBin]
        try? killTask.run()
        killTask.waitUntilExit()

        let pkillTask = Process()
        pkillTask.launchPath = "/usr/bin/pkill"
        pkillTask.arguments = ["-9", "-f", kTargetBundle]
        try? pkillTask.run()
        pkillTask.waitUntilExit()

        // 2. Remove existing bundle cleanly
        if FileManager.default.fileExists(atPath: targetURL.path) {
            do {
                try FileManager.default.removeItem(at: targetURL)
            } catch {
                // If removeItem fails, try NSWorkspace recycle
                NSWorkspace.shared.recycle([targetURL]) { [self] (_, recycleError: Error?) in
                    if let recycleError = recycleError {
                        let message = String(format: NSLocalizedString("Cannot remove the existing version at %@, error: %@", comment: ""), targetURL.path, String(describing: recycleError))
                        runAlertPanel(title: NSLocalizedString("Install Failed", comment: ""),
                                      message: message,
                                      buttonTitle: NSLocalizedString("Cancel", comment: ""))
                        endAppWithDelay()
                        return
                    }
                    proceedWithInstall(shouldWaitForTranslocationRemoval: shouldWaitForTranslocationRemoval)
                }
                return
            }
        }

        proceedWithInstall(shouldWaitForTranslocationRemoval: shouldWaitForTranslocationRemoval)
    }

    private func proceedWithInstall(shouldWaitForTranslocationRemoval: Bool) {
        if shouldWaitForTranslocationRemoval {
            progressIndicator.startAnimation(self)
            window?.beginSheet(progressSheet) { returnCode in
                DispatchQueue.main.async {
                    if returnCode == .continue {
                        self.installInputMethod(previousExists: true, previousVersionNotFullyDeactivatedWarning: false)
                    } else {
                        self.installInputMethod(previousExists: true, previousVersionNotFullyDeactivatedWarning: true)
                    }
                }
            }

            translocationRemovalStartTime = Date()
            Timer.scheduledTimer(timeInterval: kTranslocationRemovalTickInterval, target: self, selector: #selector(timerTick(_:)), userInfo: nil, repeats: true)
        } else {
            self.installInputMethod(previousExists: false, previousVersionNotFullyDeactivatedWarning: false)
        }
    }

    func installInputMethod(previousExists: Bool, previousVersionNotFullyDeactivatedWarning warning: Bool) {
        guard let targetBundle = archiveUtil?.unzipNotarizedArchive() ?? Bundle.main.path(forResource: kTargetBin, ofType: kTargetType) else {
            let message = NSLocalizedString("No installable packagess found.", comment: "")
            runAlertPanel(title: NSLocalizedString("Fatal Error", comment: ""), message: message, buttonTitle: NSLocalizedString("Abort", comment: ""))
            endAppWithDelay()
            return
        }
        let cpTask = Process()
        cpTask.launchPath = "/bin/cp"
        cpTask.arguments = ["-R", targetBundle, (kDestinationPartial as NSString).expandingTildeInPath]
        cpTask.launch()
        cpTask.waitUntilExit()

        if cpTask.terminationStatus != 0 {
            runAlertPanel(title: NSLocalizedString("Install Failed", comment: ""),
                          message: NSLocalizedString("Cannot copy the file to the destination.", comment: ""),
                          buttonTitle: NSLocalizedString("Cancel", comment: ""))
            endAppWithDelay()
            return
        }

        // Automatically remove quarantine attribute on the newly installed bundle
        let installedBundlePath = (kTargetPartialPath as NSString).expandingTildeInPath
        let xattrTask = Process()
        xattrTask.launchPath = "/usr/bin/xattr"
        xattrTask.arguments = ["-cr", installedBundlePath]
        try? xattrTask.run()
        xattrTask.waitUntilExit()

        guard let imeBundle = Bundle(path: (kTargetPartialPath as NSString).expandingTildeInPath),
              let imeIdentifier = imeBundle.bundleIdentifier
                else {
            endAppWithDelay()
            return
        }

        let imeBundleURL = imeBundle.bundleURL
        var inputSource = InputSourceHelper.inputSource(for: imeIdentifier)

        if inputSource == nil {
            NSLog("Registering input source \(imeIdentifier) at \(imeBundleURL.absoluteString).");
            let status = InputSourceHelper.registerInputSource(at: imeBundleURL)
            if !status {
                let message = String(format: NSLocalizedString("Cannot find input source %@ after registration.", comment: ""), imeIdentifier)
                runAlertPanel(title: NSLocalizedString("Fatal Error", comment: ""), message: message, buttonTitle: NSLocalizedString("Abort", comment: ""))
                endAppWithDelay()
                return
            }

            inputSource = InputSourceHelper.inputSource(for: imeIdentifier)
            if inputSource == nil {
                let message = String(format: NSLocalizedString("Cannot find input source %@ after registration.", comment: ""), imeIdentifier)
                runAlertPanel(title: NSLocalizedString("Fatal Error", comment: ""), message: message, buttonTitle: NSLocalizedString("Abort", comment: ""))
            }
        }

        var isMacOS12OrAbove = false
        if #available(macOS 12.0, *) {
            NSLog("macOS 12 or later detected.");
            isMacOS12OrAbove = true
        } else {
            NSLog("Installer runs with the pre-macOS 12 flow.");
        }

        // If the IME is not enabled, enable it. Also, unconditionally enable it on macOS 12.0+,
        // as the kTISPropertyInputSourceIsEnabled can still be true even if the IME is *not*
        // enabled in the user's current set of IMEs (which means the IME does not show up in
        // the user's input menu).

        var mainInputSourceEnabled = InputSourceHelper.inputSourceEnabled(for: inputSource!)
        if !mainInputSourceEnabled || isMacOS12OrAbove {
            mainInputSourceEnabled = InputSourceHelper.enable(inputSource: inputSource!)
            if (mainInputSourceEnabled) {
                NSLog("Input method enabled: \(imeIdentifier)");
            } else {
                NSLog("Failed to enable input method: \(imeIdentifier)");
            }
        }

        if warning {
            runAlertPanel(title: NSLocalizedString("Attention", comment: ""), message: NSLocalizedString("gg is upgraded, but please log out or reboot for the new version to be fully functional.", comment: ""), buttonTitle: NSLocalizedString("OK", comment: ""))
            endAppWithDelay()
        } else {
            if !mainInputSourceEnabled && !isMacOS12OrAbove {
                runAlertPanel(title: NSLocalizedString("Warning", comment: ""), message: NSLocalizedString("Input method may not be fully enabled. Please enable it through System Preferences > Keyboard > Input Sources.", comment: ""), buttonTitle: NSLocalizedString("Continue", comment: ""))
                endAppWithDelay()
            } else {
                installed = true

                // Expand window height and width to comfortably display the tutorial
                var frame = window?.frame ?? .zero
                let targetHeight: CGFloat = 580
                let targetWidth: CGFloat = max(frame.size.width, 680)
                if frame.size.height < targetHeight || frame.size.width < targetWidth {
                    frame.origin.y -= (targetHeight - frame.size.height)
                    frame.size.height = targetHeight
                    frame.size.width = targetWidth
                    window?.setFrame(frame, display: true, animate: true)
                }

                welcomeText.stringValue = NSLocalizedString("Installation Guide & Quick Start", comment: "")
                welcomeText.isHidden = false
                agreeText.isHidden = true
                cancelButton.isHidden = true
                actionButton.title = NSLocalizedString("Close Installer", comment: "")
                actionButton.isEnabled = true

                setupPostInstallButtons()
                renderInstallationTutorial()
            }
        }
    }

    func endAppWithDelay() {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            NSApp.terminate(self)
        }
    }

    @IBAction func cancelAction(_ sender: AnyObject) {
        NSApp.terminate(self)
    }

    func windowWillClose(_ Notification: Notification) {
        NSApp.terminate(self)
    }

    func updateAutoClosingMessage(seconds: Int) {
        agreeText.stringValue = String.localizedStringWithFormat(
            NSLocalizedString("The installer will close itself in %d second(s).", comment: ""),
            seconds)
    }

    func scheduleAutoClose() {
        var counter = 60
        updateAutoClosingMessage(seconds: counter)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            counter -= 1
            if counter == 0 {
                timer.invalidate()
                self?.endAppWithDelay()
            } else {
                self?.updateAutoClosingMessage(seconds: counter)
            }
        }
    }

    @objc func openKeyboardSettingsAction(_ sender: Any?) {
        let urls = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ]
        for urlStr in urls {
            if let url = URL(string: urlStr), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc func openSecuritySettingsAction(_ sender: Any?) {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            "x-apple.systempreferences:com.apple.preference.security?General",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for urlStr in urls {
            if let url = URL(string: urlStr), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func setupPostInstallButtons() {
        guard let contentView = window?.contentView else { return }

        let kbBtn = NSButton(
            title: NSLocalizedString("Open Keyboard Settings", comment: ""),
            target: self,
            action: #selector(openKeyboardSettingsAction(_:))
        )
        kbBtn.bezelStyle = .rounded
        kbBtn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(kbBtn)

        let secBtn = NSButton(
            title: NSLocalizedString("Open Privacy & Security", comment: ""),
            target: self,
            action: #selector(openSecuritySettingsAction(_:))
        )
        secBtn.bezelStyle = .rounded
        secBtn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(secBtn)

        NSLayoutConstraint.activate([
            kbBtn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            kbBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            secBtn.leadingAnchor.constraint(equalTo: kbBtn.trailingAnchor, constant: 10),
            secBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        self.openKeyboardSettingsButton = kbBtn
        self.openSecuritySettingsButton = secBtn
    }

    private func renderInstallationTutorial() {
        let isZhHant = Locale.preferredLanguages.first?.hasPrefix("zh") ?? true

        let titleFont = NSFont.boldSystemFont(ofSize: 18)
        let sectionFont = NSFont.boldSystemFont(ofSize: 14)
        let boldFont = NSFont.boldSystemFont(ofSize: 13)
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let tipFont = NSFont.systemFont(ofSize: 12)

        let textColor = NSColor.textColor
        let secondaryColor = NSColor.secondaryLabelColor
        let accentColor = NSColor.systemBlue

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        let content = NSMutableAttributedString()

        func append(_ text: String, font: NSFont, color: NSColor = textColor) {
            let attr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
            content.append(NSAttributedString(string: text, attributes: attr))
        }

        func appendDivider() {
            let divAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: paragraphStyle
            ]
            content.append(NSAttributedString(string: "───────────────────────────────────────────────────────\n\n", attributes: divAttr))
        }

        if isZhHant {
            append("gg 輸入法 安裝成功！\n", font: titleFont, color: accentColor)
            append("請依照以下 3 個步驟啟用輸入法並快速上手：\n\n", font: bodyFont, color: secondaryColor)
            appendDivider()

            append("步驟一：安全性放行（針對未簽名版本提示）\n", font: sectionFont)
            append("• 若系統跳出「無法驗證開發者」或提示已被阻擋：\n", font: bodyFont)
            append("  請點擊下方「 開啟『隱私與安全性』」按鈕，滑動至最下方，在安全性區塊點選「仍要打開」或「允許」。\n", font: bodyFont)
            append("• 本安裝程式已自動為您清除輸入法本體之隔離標籤 (Quarantine)。\n\n", font: tipFont, color: secondaryColor)
            appendDivider()

            append("步驟二：啟用與切換輸入法\n", font: sectionFont)
            append("  1. 點擊下方「開啟『鍵盤』設定」按鈕。\n", font: bodyFont)
            append("  2. 前往「文字輸入」>「輸入方式」點選「編輯...」。\n", font: bodyFont)
            append("  3. 點選左下角「+」，在「繁體中文」分類中找到並新增「gg 輸入法」。\n", font: bodyFont)
            append("  提示：建議登出 macOS 帳號或重新開機，系統能更完整載入輸入法。\n\n", font: tipFont, color: secondaryColor)
            appendDivider()

            append("使用簡介\n", font: sectionFont)
            append("1. 【中英混打雙軌引擎】：\n", font: boldFont)
            append("   • 注音打字中可直接鍵入英文字詞，無須頻繁切換中英模式！\n", font: bodyFont)
            append("   • 按下「Shift 鍵」可快速臨時切換大寫英文字母或進入英文模式。\n", font: bodyFont)
            append("2. 【數字輸入與選字】：\n", font: boldFont)
            append("   • 候選字清單提供 1 ~ 9 快速數字鍵選字。\n", font: bodyFont)
            append("   • 需要直接輸入純數字時，於打字時按「Enter 鍵」直接送出，或直接使用數字鍵盤輸入。\n", font: bodyFont)
            append("3. 【空白鍵智慧選字】：\n", font: boldFont)
            append("   • 輸入注音後直接按下「空白鍵」，系統將自動預測並選取最精準的詞彙。\n", font: bodyFont)
        } else {
            append("gg IME Installed Successfully!\n", font: titleFont, color: accentColor)
            append("Follow the 3 steps below to enable and get started:\n\n", font: bodyFont, color: secondaryColor)
            appendDivider()

            append("Step 1: Security & Gatekeeper Approval\n", font: sectionFont)
            append("• If macOS prompts 'unidentified developer' or blocks the app:\n", font: bodyFont)
            append("  Click 'Privacy & Security' below, scroll to the bottom, and click 'Open Anyway'.\n", font: bodyFont)
            append("• The installer has automatically cleared quarantine flags on the app bundle.\n\n", font: tipFont, color: secondaryColor)
            appendDivider()

            append("Step 2: Enable & Switch to gg IME\n", font: sectionFont)
            append("  1. Click 'Keyboard Settings' below.\n", font: bodyFont)
            append("  2. Go to 'Text Input' > 'Input Sources' > 'Edit...'.\n", font: bodyFont)
            append("  3. Click '+' and add 'gg IME' under Traditional Chinese.\n", font: bodyFont)
            append("Tip: Logging out or restarting macOS is recommended for the system to reload input sources.\n\n", font: tipFont, color: secondaryColor)
            appendDivider()

            append("？\n", font: sectionFont)
            append("1. Mixed Chinese-English Typing:\n", font: boldFont)
            append("   • Type English words directly during Bopomofo input without switching modes!\n", font: bodyFont)
            append("   • Press 'Shift' to quickly enter uppercase or toggle English.\n", font: bodyFont)
            append("2. Numeric Input & Candidate Selection:\n", font: boldFont)
            append("   • Use number keys 1~9 to select candidates quickly.\n", font: bodyFont)
            append("   • Press 'Enter' to commit raw numbers directly.\n", font: bodyFont)
            append("3. Spacebar Candidate Selection:\n", font: boldFont)
            append("   • Press Spacebar after typing readings to automatically select the most relevant words.\n", font: bodyFont)
        }

        textView.textStorage?.setAttributedString(content)
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}
