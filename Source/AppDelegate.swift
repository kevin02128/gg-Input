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
import FSEventStreamHelper
import InputMethodKit
import InputSourceHelper

@objc(AppDelegate)
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow?
    private var preferencesWindowController: PreferencesWindowController?
    private var fsStreamHelper: FSEventStreamHelper?
    private var serviceProvider = ServiceProvider()
    private var serviceProviderHelper = ServiceProviderInputHelper()

    func updateUserPhrases() {
        LanguageModelManager.loadUserPhrases(
            enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
        LanguageModelManager.loadUserPhraseReplacement()

        fsStreamHelper?.delegate = nil
        fsStreamHelper?.stop()
        fsStreamHelper = FSEventStreamHelper(
            path: LanguageModelManager.dataFolderPath, queue: DispatchQueue(label: "User Phrases"))
        fsStreamHelper?.delegate = self
        _ = fsStreamHelper?.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LanguageModelManager.setupDataModelValueConverter()
        LanguageModelManager.loadDataModel(.bopomofo)
        updateUserPhrases()

        if UserDefaults.standard.object(forKey: kBeepUponInputErrorKey) == nil {
            UserDefaults.standard.set(true, forKey: kBeepUponInputErrorKey)
            UserDefaults.standard.synchronize()
        }

        NotificationCenter.default.addObserver(
            forName: .userPhraseLocationDidChange, object: nil, queue: OperationQueue.main
        ) { notification in
            self.updateUserPhrases()
        }

        serviceProvider.delegate = serviceProviderHelper
        NSApp.servicesProvider = serviceProvider
    }

    func applicationWillTerminate(_ notification: Notification) {
        LanguageModelManager.userOverrideModel.saveImmediately()
    }

    @MainActor
    @objc func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showAndActivate()
    }

    @objc func uninstallGG() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Uninstall gg Input Method", comment: "")
        alert.informativeText = NSLocalizedString(
            "Are you sure you want to uninstall gg? The system will switch to the default English input source and remove the app.",
            comment: "")
        alert.addButton(withTitle: NSLocalizedString("Uninstall", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let checkbox = NSButton(
            checkboxWithTitle: NSLocalizedString("Delete user phrases and preferences", comment: ""),
            target: nil, action: nil)
        checkbox.state = .off
        alert.accessoryView = checkbox

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            performUninstall(deleteUserData: checkbox.state == .on)
        }
    }

    private func performUninstall(deleteUserData: Bool) {
        guard let bundleID = Bundle.main.bundleIdentifier,
              InputSourceHelper.selectInputSource(withID: "com.apple.keylayout.ABC")
                || InputSourceHelper.selectInputSource(withID: "com.apple.keylayout.US"),
              InputSourceHelper.disableAllInputSources(for: bundleID)
        else {
            let error = NSAlert()
            error.messageText = NSLocalizedString("Unable to Prepare gg for Uninstall", comment: "")
            error.informativeText = NSLocalizedString(
                "gg could not switch to an English keyboard or disable its input source. Nothing was removed. Try again after selecting another input source.",
                comment: "")
            error.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            error.runModal()
            return
        }

        let deleteFlag = deleteUserData ? "1" : "0"
        let homeDir = NSHomeDirectory()
        _ = InputSourceHelper.cleanupHIToolboxInputSourcesForUninstall(
            plistPath: "\(homeDir)/Library/Preferences/com.apple.HIToolbox.plist",
            bundleID: bundleID
        )
        let command = """
        set -e
        rm -rf '\(homeDir)/Library/Input Methods/gg.app'
        rm -rf '\(homeDir)/Library/Input Methods/Anev.app'
        rm -rf '/Library/Input Methods/gg.app'
        rm -rf '/Library/Input Methods/Anev.app'
        rm -rf '/Library/Input Methods/gg.localized'
        /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u '\(homeDir)/Library/Input Methods/gg.app' 2>/dev/null || true
        /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u '/Library/Input Methods/gg.app' 2>/dev/null || true
        /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u '/Library/Input Methods/Anev.app' 2>/dev/null || true
        /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u '/Library/Input Methods/gg.localized/gg.app' 2>/dev/null || true
        for DERIVED in '\(homeDir)'/Library/Developer/Xcode/DerivedData/gg-*/Build/Products/*/gg.app; do
            [ -d "$DERIVED" ] && /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$DERIVED" 2>/dev/null || true
        done
        rm -f "$(getconf DARWIN_USER_CACHE_DIR)"com.apple.IntlDataCache.le* 2>/dev/null || true
        if [ '\(deleteFlag)' = '1' ]; then
            rm -rf '\(homeDir)/Library/Application Support/gg'
            rm -f '\(homeDir)/Library/Preferences/com.kevin.inputmethod.gg.plist'
            defaults delete com.kevin.inputmethod.gg 2>/dev/null || true
        fi
        killall -9 cfprefsd TextInputMenuAgent TextInputSwitcher CursorUIViewService 2>/dev/null || true
        """

        let escapedCommand = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escapedCommand)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            let appleScript = NSAppleScript(source: script)
            var errorDict: NSDictionary?
            let succeeded = appleScript?.executeAndReturnError(&errorDict) != nil && errorDict == nil
            DispatchQueue.main.async {
                if succeeded {
                    NSApp.terminate(nil)
                    return
                }
                let error = NSAlert()
                error.messageText = NSLocalizedString("Unable to Uninstall gg", comment: "")
                error.informativeText = NSLocalizedString(
                    "The administrator action was cancelled or failed. gg was not fully removed.",
                    comment: "")
                error.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                error.runModal()
            }
        }
    }
}

extension AppDelegate: FSEventStreamHelperDelegate {
    func helper(_ helper: FSEventStreamHelper, didReceive events: [FSEventStreamHelper.Event]) {
        DispatchQueue.main.async {
            LanguageModelManager.loadUserPhrases(
                enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
            LanguageModelManager.loadUserPhraseReplacement()
        }
    }
}

extension AppDelegate {
    private func open(userFileAt path: String) {
        func checkIfUserFilesExist() -> Bool {
            if !LanguageModelManager.checkIfUserLanguageModelFilesExist() {
                let content = String(
                    format: NSLocalizedString(
                        "Please check the permission of the path at \"%@\".", comment: ""),
                    LanguageModelManager.dataFolderPath)
                NonModalAlertWindowController.shared.show(
                    title: NSLocalizedString("Failed to Create the User Phrase File", comment: ""),
                    content: content, confirmButtonTitle: NSLocalizedString("OK", comment: ""),
                    cancelButtonTitle: nil, cancelAsDefault: false, delegate: nil)
                return false
            }
            return true
        }

        if !checkIfUserFilesExist() {
            return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    @objc func openUserPhrases(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.userPhrasesDataPathMcBopomofo)
    }

    @objc func openUserPhrasesPlainBopomofo(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.userPhrasesDataPathPlainBopomofo)
    }

    @objc func openExcludedPhrasesPlainBopomofo(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.excludedPhrasesDataPathPlainBopomofo)
    }

    @objc func openExcludedPhrasesMcBopomofo(_ sender: Any?) {
        open(userFileAt: LanguageModelManager.excludedPhrasesDataPathMcBopomofo)
    }
}
