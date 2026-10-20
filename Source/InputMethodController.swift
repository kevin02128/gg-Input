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

import CandidateUI
import Carbon
import Cocoa
import InputMethodKit
import InputSourceHelper
import NotifierUI
import OpenCCBridge
import SystemCharacterInfo
import TooltipUI

extension Bool {
    fileprivate var state: NSControl.StateValue {
        self ? .on : .off
    }
}

private let kMinKeyLabelSize: CGFloat = 10

internal var gCurrentCandidateController: CandidateController?

extension CandidateController {
    static let horizontal = HorizontalCandidateController()
    static let vertical = VerticalCandidateController()
}

@objc(McBopomofoInputMethodController)
class McBopomofoInputMethodController: IMKInputController {

    private static let tooltipController = TooltipController()

    // MARK: -

    var currentClient: Any?
    var keyHandler: KeyHandler = KeyHandler()
    var state: InputState = InputState.Empty()
    private var lastReviewedGridRevision: UInt64 = 0

    // Share the stored issues, so a set of issues is shown as notification only once.
    static var latestUserFileIssues: [String] = []

    // MARK: - IMKInputController methods

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        keyHandler.delegate = self
        keyHandler.onUserRejectedReviewedCandidate = { reading, rejected, kept, leftContext in
            WTFNeuralReranker.shared.recordNegativeFeedback(
                reading: reading,
                rejected: rejected,
                kept: kept,
                leftContext: leftContext
            )
        }
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Input Method Menu")

        let chineseConversionItem = menu.addItem(
            withTitle: NSLocalizedString("Convert to Simplified Chinese", comment: ""),
            action: #selector(toggleChineseConverter(_:)), keyEquivalent: "g")
        chineseConversionItem.keyEquivalentModifierMask = [.command, .control]
        chineseConversionItem.state = Preferences.chineseConversionEnabled.state

        let halfWidthPunctuationItem = menu.addItem(
            withTitle: NSLocalizedString("Use Half-Width Punctuations", comment: ""),
            action: #selector(toggleHalfWidthPunctuation(_:)), keyEquivalent: "h")
        halfWidthPunctuationItem.keyEquivalentModifierMask = [.command, .control]
        halfWidthPunctuationItem.state = Preferences.halfWidthPunctuationEnabled.state
        let associatedPhrasesItem = menu.addItem(
            withTitle: NSLocalizedString("Associated Phrases", comment: ""),
            action: #selector(toggleAssociatedPhrasesEnabled(_:)), keyEquivalent: "")
        associatedPhrasesItem.state = Preferences.associatedPhrasesEnabled.state

        let inputMode = keyHandler.inputMode

        // Only Bopomofo mode supports Bopomofo Font Annotation. If support is
        // on, ensure that the user has a way to disable it. Otherwise, only
        // show the item when it is set to show in the input menu.
        if inputMode == .bopomofo
            && (Preferences.showBopomofoFontAnnotationSupportItemInInputMenu
                || Preferences.bopomofoFontAnnotationSupportEnabled)
        {
            let bopomofoFontAnnotationSupportItem = menu.addItem(
                withTitle: NSLocalizedString("Bopomofo Font Annotation Support", comment: ""),
                action: #selector(toggleBopomofoFontAnnotationSupport(_:)), keyEquivalent: "")
            bopomofoFontAnnotationSupportItem.state =
                Preferences.bopomofoFontAnnotationSupportEnabled.state
        }

        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
        if inputMode == .bopomofo && optionKeyPressed {
            let phaseReplacementItem = menu.addItem(
                withTitle: NSLocalizedString("Use Phrase Replacement", comment: ""),
                action: #selector(togglePhraseReplacement(_:)), keyEquivalent: "")
            phaseReplacementItem.state = Preferences.phraseReplacementEnabled.state
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: NSLocalizedString("User Phrases", comment: ""), action: nil,
            keyEquivalent: "")

        if inputMode == .plainBopomofo {
            if Preferences.enableUserPhrasesInPlainBopomofo {
                menu.addItem(
                    withTitle: NSLocalizedString("Edit User Phrases", comment: ""),
                    action: #selector(openUserPhrasesPlainBopomofo(_:)), keyEquivalent: "")
            }
            menu.addItem(
                withTitle: NSLocalizedString("Edit Excluded Phrases", comment: ""),
                action: #selector(openExcludedPhrasesPlainBopomofo(_:)), keyEquivalent: "")
        } else {
            menu.addItem(
                withTitle: NSLocalizedString("Edit User Phrases", comment: ""),
                action: #selector(openUserPhrases(_:)), keyEquivalent: "")
            menu.addItem(
                withTitle: NSLocalizedString("Edit Excluded Phrases", comment: ""),
                action: #selector(openExcludedPhrasesMcBopomofo(_:)), keyEquivalent: "")
            if optionKeyPressed {
                menu.addItem(
                    withTitle: NSLocalizedString("Edit Phrase Replacement Table", comment: ""),
                    action: #selector(openPhraseReplacementMcBopomofo(_:)), keyEquivalent: "")
            }
        }

        menu.addItem(
            withTitle: NSLocalizedString("Reload User Phrases", comment: ""),
            action: #selector(reloadUserPhrases(_:)), keyEquivalent: "")

        if !McBopomofoInputMethodController.latestUserFileIssues.isEmpty {
            let menuItem = NSMenuItem(
                title: NSLocalizedString("Show Issues in User Files", comment: ""),
                action: #selector(showUserFileIssues(_:)), keyEquivalent: "")
            menu.addItem(menuItem)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: NSLocalizedString("McBopomofo Preferences", comment: ""),
            action: #selector(showPreferences(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Check for Updates…", comment: ""),
            action: #selector(checkForUpdate(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("About McBopomofo…", comment: ""),
            action: #selector(showAbout(_:)), keyEquivalent: "")
        return menu
    }

    // MARK: - IMKStateSetting protocol methods

    override func activateServer(_ client: Any!) {
        Preferences.chooseCandidateUsingSpace = false
        UserDefaults.standard.synchronize()

        // Override the keyboard layout. Use US if not set.
        (client as? IMKTextInput)?.overrideKeyboard(
            withKeyboardNamed: Preferences.basisKeyboardLayout)
        // reset the state
        currentClient = client

        keyHandler.clear()
        keyHandler.syncWithPreferences()

        (NSApp.delegate as? AppDelegate)?.checkForUpdate()
    }

    override func deactivateServer(_ client: Any!) {
        currentClient = nil
        WTFMixedInputManager.shared.clear()
        hideTooltip()
        keyHandler.clear()
        self.handle(state: .Deactivated(), client: client)
    }

    override func setValue(_ value: Any!, forTag tag: Int, client: Any!) {
        let newInputMode = InputMode(rawValue: value as? String ?? InputMode.bopomofo.rawValue)
        LanguageModelManager.loadDataModel(newInputMode)
        // Restore the client layout even when the internal input mode is unchanged.
        (client as? IMKTextInput)?.overrideKeyboard(
            withKeyboardNamed: Preferences.basisKeyboardLayout)
        if keyHandler.inputMode != newInputMode {
            UserDefaults.standard.synchronize()
            // Remember to override the keyboard layout again -- treat this as an activate event.
            keyHandler.clear()
            keyHandler.inputMode = newInputMode
            self.handle(state: .Empty(), client: client)
        }

        // Since setValue is called after activateServer, show user file issues here, if any.
        checkUserFileIssues()
    }

    // MARK: - IMKServerInput protocol methods

    override func commitComposition(_ client: Any!) {
        if WTFMixedInputManager.shared.isPureEnglishMode {
            let buf = WTFMixedInputManager.shared.currentBuffer
            if !buf.isEmpty {
                commit(text: buf, isEnglish: true, client: client)
            }
        }
        WTFMixedInputManager.shared.clear()
        hideTooltip()
        keyHandler.handleForceCommit(stateCallback: { newState in
            self.handle(state: newState, client: client)
        })
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        let events: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        return Int(events.rawValue)
    }

    override func handle(_ maybeEvent: NSEvent!, client: Any!) -> Bool {
        // nil may be passed, applefeedback://FB11472618
        guard let event = maybeEvent else {
            commitComposition(client)
            return false
        }

        if event.type == .keyUp {
            if (state is InputState.Empty) && !WTFMixedInputManager.shared.isPureEnglishMode {
                return false
            }
            // Handle key up events during active input state.
            //
            // This prevents double-space from affecting the current input.
            // While macOS may normally insert a period on double space, this
            // should be suppressed when there is an active composing buffer or
            // candidate window.
            return true
        }

        if event.type == .flagsChanged {
            if Preferences.switchInputSourceUponCommandKeyPressEnabled,
               (event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand)),
               event.modifierFlags.contains(.command) {
                keyHandler.clear()
                handle(state: InputState.SwitchingInputSource(sourceID: Preferences.switchInputSourceUponCommandKeyPressInputSourceID), client: client)
                return false
            }
            let functionKeyKeyboardLayoutID = Preferences.functionKeyboardLayout
            let basisKeyboardLayoutID = Preferences.basisKeyboardLayout

            if functionKeyKeyboardLayoutID == basisKeyboardLayoutID {
                return false
            }

            let includeShift = Preferences.functionKeyKeyboardLayoutOverrideIncludeShiftKey
            let notShift = NSEvent.ModifierFlags(rawValue: ~(NSEvent.ModifierFlags.shift.rawValue))
            if event.modifierFlags.contains(notShift)
                || (event.modifierFlags.contains(.shift) && includeShift)
            {
                (client as? IMKTextInput)?.overrideKeyboard(
                    withKeyboardNamed: functionKeyKeyboardLayoutID)
                return false
            }
            (client as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: basisKeyboardLayoutID)
            return false
        }

        // gg 輸入法 (公司: wtf) - 中英混打雙軌模組攔截
        if WTFMixedInputManager.shared.isEnabled {
            if let handled = handleWTFMixedInput(event: event, client: client) {
                return handled
            }
        }

        var textFrame = NSRect.zero
        let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(
            forCharacterIndex: 0, lineHeightRectangle: &textFrame)
        let useVerticalMode =
            (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false
        let input = KeyHandlerInput(event: event, isVerticalMode: useVerticalMode)

        let result = keyHandler.handle(input: input, state: state) { newState in
            self.handle(state: newState, client: client)
        } errorCallback: {
            if Preferences.beepUponInputError {
                NSSound.beep()
            }
        }

        if result, WTFMixedInputManager.shared.isEnabled, event.type == .keyDown {
            postProcessWTFMixedInput(event: event, client: client)
        } else if !result, event.type == .keyDown {
            let keyCode = event.keyCode
            // Backspace (51) or arrow keys (123-126) when buffer is empty: reset committed context
            if keyCode == 51 || (keyCode >= 123 && keyCode <= 126) {
                WTFMixedInputManager.shared.resetCommittedContext()
            } else if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      let chars = event.characters, !chars.isEmpty,
                      let first = chars.first, first.isASCII, !first.isNewline,
                      first >= " " && first <= "~" {
                // Direct pass-through ASCII input (e.g. CapsLock English mode or unconsumed numbers/symbols)
                if WTFMixedInputManager.shared.panguSpacingEnabled,
                   let prev = WTFMixedInputManager.shared.lastCommittedChar,
                   WTFMixedInputManager.needsPanguSpace(left: prev, right: first) {
                    commit(text: chars, isEnglish: true, client: client)
                    return true
                }
                WTFMixedInputManager.shared.lastCommittedChar = chars.last
                WTFMixedInputManager.shared.lastCommitWasEnglishWord = WTFMixedInputManager.isASCIIAlphanumeric(first)
            }
        }

        return result
    }

    // MARK: - Menu Items

    @objc override func showPreferences(_ sender: Any?) {
        super.showPreferences(sender)
    }

    @objc func toggleChineseConverter(_ sender: Any?) {
        let enabled = Preferences.toggleChineseConversionEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Chinese Conversion On", comment: "")
                : NSLocalizedString("Chinese Conversion Off", comment: ""))
        if let currentClient = currentClient {
            keyHandler.clear()
            self.handle(state: InputState.Empty(), client: currentClient)
        }
    }

    @objc func toggleHalfWidthPunctuation(_ sender: Any?) {
        let enabled = Preferences.toggleHalfWidthPunctuationEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Half-Width Punctuation On", comment: "")
                : NSLocalizedString("Half-Width Punctuation Off", comment: ""))
        if let currentClient = currentClient {
            keyHandler.clear()
            self.handle(state: InputState.Empty(), client: currentClient)
        }
    }

    @objc func toggleAssociatedPhrasesEnabled(_ sender: Any?) {
        _ = Preferences.toggleAssociatedPhrasesEnabled()
    }

    @objc func toggleBopomofoFontAnnotationSupport(_ sender: Any?) {
        let enabled = Preferences.toggleBopomofoFontAnnotationSupportEnabled()
        NotifierController.notify(
            message: enabled
                ? NSLocalizedString("Bopomofo Font Annotation Support On", comment: "")
                : NSLocalizedString("Bopomofo Font Annotation Support Off", comment: ""))
    }

    @objc func togglePhraseReplacement(_ sender: Any?) {
        let enabled = Preferences.togglePhraseReplacementEnabled()
        LanguageModelManager.phraseReplacementEnabled = enabled
    }

    @objc func checkForUpdate(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.checkForUpdate(forced: true)
    }

    @objc func openUserPhrases(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openUserPhrases(sender)
    }

    @objc func openUserPhrasesPlainBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openUserPhrasesPlainBopomofo(sender)
    }

    @objc func openExcludedPhrasesPlainBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openExcludedPhrasesPlainBopomofo(sender)
    }

    @objc func openExcludedPhrasesMcBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openExcludedPhrasesMcBopomofo(sender)
    }

    @objc func openPhraseReplacementMcBopomofo(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openPhraseReplacementMcBopomofo(sender)
    }

    @objc func reloadUserPhrases(_ sender: Any?) {
        LanguageModelManager.loadUserPhrases(
            enableForPlainBopomofo: Preferences.enableUserPhrasesInPlainBopomofo)
        LanguageModelManager.loadUserPhraseReplacement()

        // Empty the issues so that if there are still the same issues, a
        // notification will be shown.
        McBopomofoInputMethodController.latestUserFileIssues = []
        checkUserFileIssues()
    }

    @objc func showUserFileIssues(_ sender: Any?) {
        let header = NSLocalizedString(
            "Issues were found in the following user phrase files:", comment: "")
        let report =
            header + "\n\n"
            + McBopomofoInputMethodController.latestUserFileIssues.joined(separator: "\n")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss.SSS"
        let dateString = formatter.string(from: now)
        let fileName = "UserFileIssues-\(dateString).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(fileURL)
        } catch {
            NSLog("Failed to write report to temporary file: \(error)")
            return
        }
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

}

// MARK: - State Handling

extension McBopomofoInputMethodController {

    func handle(state newState: InputState, client: Any?) {
        let previous = state
        state = newState

        switch newState {
        case let newState as InputState.Deactivated:
            WTFMixedInputManager.shared.clear()
            WTFMixedInputManager.shared.resetCommittedContext()
            hideTooltip()
            handle(state: newState, previous: previous, client: client)
            state = .Empty()
        case let newState as InputState.SwitchingInputSource:
            WTFMixedInputManager.shared.clear()
            WTFMixedInputManager.shared.resetCommittedContext()
            hideTooltip()
            handle(state: newState, previous: previous, client: client)
            state = .Empty()
            if !InputSourceHelper.selectInputSource(withID: newState.sourceID) {
                NSLog("Unable to switch to input source: %@", newState.sourceID)
            }
        case let newState as InputState.Empty:
            if !WTFMixedInputManager.shared.isPureEnglishMode {
                WTFMixedInputManager.shared.clear()
                hideTooltip()
            }
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.EmptyIgnoringPreviousState:
            if !WTFMixedInputManager.shared.isPureEnglishMode {
                WTFMixedInputManager.shared.clear()
                hideTooltip()
            }
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Committing:
            if !WTFMixedInputManager.shared.isPureEnglishMode {
                WTFMixedInputManager.shared.clear()
                hideTooltip()
            }
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Inputting:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Marking:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ChoosingCandidate:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.AssociatedPhrases:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.AssociatedPhrasesPlain:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingFeature:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingDateMacro:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Number:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.IcuTransform:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Big5:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.SelectingDictionary:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.ShowingCharInfo:
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.CustomMenu:
            handle(state: newState, previous: previous, client: client)
        default:
            break
        }
    }

    private func commit(text: String, isEnglish: Bool = false, skipCorrection: Bool = false, client: Any!) {

        func convertToSimplifiedChineseIfRequired(_ text: String) -> String {
            if !Preferences.chineseConversionEnabled {
                return text
            }
            if Preferences.chineseConversionStyle == .model {
                return text
            }
            return OpenCCBridge.shared.convertToSimplified(text) ?? ""
        }

        var buffer = text
        buffer = isEnglish ? buffer : convertToSimplifiedChineseIfRequired(buffer)
        if buffer.isEmpty {
            return
        }

        // Pangu Auto-Spacing (中英自動空格):
        // Automatically insert a half-width space at CJK <-> ASCII alphanumeric boundaries,
        // both within mixed phrases and across consecutive Chinese/English commits.
        buffer = WTFMixedInputManager.shared.applyPanguSpacing(
            to: buffer,
            isEnglishWord: isEnglish && buffer.count > 1 && !buffer.hasSuffix(" ")
        )

        (client as? IMKTextInput)?.insertText(
            buffer, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))

        // 中文送出後，若開啟聯想字且非英文模式，觸發下一字聯想 (對齊開發書第 7 章)
        if !isEnglish && Preferences.associatedPhrasesEnabled && WTFMixedInputManager.shared.currentBuffer.isEmpty {
            if let lastChar = buffer.last, lastChar >= "\u{4E00}" && lastChar <= "\u{9FA5}" {
                if let nextWord = keyHandler.findTopAssociatedPhraseSuffix(forPrefix: String(lastChar)) {
                    WTFMixedInputManager.shared.associatedSuggestion = nextWord
                    showTooltipForMixedInput("聯想: \(nextWord)  [Tab 補全]", client: client)
                } else {
                    WTFMixedInputManager.shared.associatedSuggestion = nil
                }
            } else {
                WTFMixedInputManager.shared.associatedSuggestion = nil
            }
        }
    }

    private func handle(state: InputState.Deactivated, previous: InputState, client: Any?) {
        currentClient = nil

        gCurrentCandidateController?.delegate = nil
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        switch previous {
        case let previous as InputState.NotEmpty:
            commit(text: previous.composingBuffer, client: client)
        case is InputState.Big5,
            is InputState.Number,
            is InputState.IcuTransform:
            client.setMarkedText(
                "", selectionRange: NSMakeRange(0, 0), replacementRange: NSMakeRange(0, 0))
        default:
            break
        }

        // Unlike the Empty state handler, we don't call client.setMarkedText() here:
        // there's no point calling setMarkedText() with an empty string as the session
        // is being deactivated anyway, and we have found issues with how certains app
        // could not handle setMarkedText() at this point (see GitHub issue #346).
    }

    private func handle(state: InputState.Empty, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(
        state: InputState.EmptyIgnoringPreviousState, previous: InputState, client: Any!
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Committing, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        let poppedText = state.poppedText
        if !poppedText.isEmpty {
            commit(text: poppedText, skipCorrection: true, client: client)
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handle(state: InputState.Inputting, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        var effectiveState = state
        let currentRev = keyHandler.gridRevision

        if currentRev != lastReviewedGridRevision {
            lastReviewedGridRevision = currentRev
            // 只有組字緩衝區至少 2 個字時才需要整句重排（單字無上下文，跳過可節省 50% 以上不必要的推論以極大降低延遲）
            if effectiveState.composingBuffer.count >= 2,
               Preferences.wtfContextCorrectionEnabled && WTFNeuralReranker.shared.isEnabled {
                let hypotheses = keyHandler.currentNBestHypotheses(8)
                if !hypotheses.isEmpty,
                   let reviewedWords = WTFNeuralReranker.shared.reviewNBestHypotheses(hypotheses) {
                    keyHandler.reviewedNodeValues = reviewedWords
                    if let rebuilt = keyHandler.buildInputtingState(withNodeValues: reviewedWords) as? InputState.Inputting {
                        effectiveState = rebuilt
                        self.state = rebuilt
                    }
                }
            }
        }

        // Live Pangu spacing when starting a new Chinese/Bopomofo composition right after committed English/numbers
        if (previous is InputState.Empty || previous is InputState.EmptyIgnoringPreviousState),
           WTFMixedInputManager.shared.panguSpacingEnabled,
           let lastChar = WTFMixedInputManager.shared.lastCommittedChar,
           WTFMixedInputManager.isASCIIAlphanumeric(lastChar),
           let firstComposing = effectiveState.composingBuffer.first,
           WTFMixedInputManager.isBopomofoOrCJK(firstComposing) {
            client.insertText(" ", replacementRange: NSMakeRange(NSNotFound, NSNotFound))
            WTFMixedInputManager.shared.lastCommittedChar = " "
            WTFMixedInputManager.shared.lastCommitWasEnglishWord = false
        }

        let attrString = effectiveState.attributedString
        let safeCursor = min(max(0, Int(effectiveState.cursorIndex)), attrString.length)
        client.setMarkedText(
            attrString, selectionRange: NSMakeRange(safeCursor, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        if !effectiveState.tooltip.isEmpty {
            show(
                tooltip: effectiveState.tooltip, composingBuffer: effectiveState.composingBuffer,
                cursorIndex: effectiveState.cursorIndex, client: client)
        }
    }

    private func handle(state: InputState.Marking, previous: InputState, client: Any?) {
        gCurrentCandidateController?.visible = false
        guard let client = client as? IMKTextInput else {
            hideTooltip()
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))

        if state.tooltip.isEmpty {
            hideTooltip()
        } else {
            show(
                tooltip: state.tooltip, composingBuffer: state.composingBuffer,
                cursorIndex: state.markerIndex, client: client)
        }
    }

    private func handle(state: InputState.ChoosingCandidate, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }

        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            state.attributedString, selectionRange: NSMakeRange(Int(state.cursorIndex), 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.AssociatedPhrases, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }

        let previousState = state.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Inputting:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(
        state: InputState.AssociatedPhrasesPlain, previous: InputState, client: Any?
    ) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.SelectingFeature, previous: InputState, client: Any?) {
        handleStateWithSimpleCandidateWindow(state: state, previous: previous, client: client)
    }

    private func handle(state: InputState.SelectingDateMacro, previous: InputState, client: Any?) {
        handleStateWithSimpleCandidateWindow(state: state, previous: previous, client: client)
    }

    private func handleSpecialInputWithCandidateWindow(state: InputState, composingBuffer: String, candidateCount: Int, client: Any?) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        client.setMarkedText(
            composingBuffer,
            selectionRange: NSMakeRange(
                (composingBuffer as NSString).length,
                0
            ),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound)
        )
        if candidateCount > 0 {
            show(candidateWindowWith: state, client: client)
        }
    }


    private func handle(state: InputState.Number, previous: InputState, client: Any?) {
        handleSpecialInputWithCandidateWindow(state: state, composingBuffer: state.composingBuffer, candidateCount: state.candidateCount, client: client)
    }

    private func handle(state: InputState.IcuTransform, previous: InputState, client: Any?) {
        handleSpecialInputWithCandidateWindow(state: state, composingBuffer: state.composingBuffer, candidateCount: state.candidateCount, client: client)
    }

    private func handle(state: InputState.Big5, previous: InputState, client: Any?) {
        handleStateForCustomInput(
            composingBuffer: state.composingBuffer, previous: previous, client: client)
    }

    private func handle(state: InputState.SelectingDictionary, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        let previousState = state.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer

        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Marking:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.ShowingCharInfo, previous: InputState, client: Any?) {

        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        let previousState = state.previousState.previousState
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        switch previousState {
        case let previousState as InputState.ChoosingCandidate:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        case let previousState as InputState.Marking:
            client.setMarkedText(
                previousState.attributedString,
                selectionRange: NSMakeRange(Int(previousState.cursorIndex), 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        default:
            break
        }
        show(candidateWindowWith: state, client: client)
    }

    private func handle(state: InputState.CustomMenu, previous: InputState, client: Any?) {
        hideTooltip()
        guard let client = client as? IMKTextInput else {
            gCurrentCandidateController?.visible = false
            return
        }
        show(candidateWindowWith: state, client: client)
    }
}

// MARK: -

extension McBopomofoInputMethodController {
    private func handleStateForCustomInput(
        composingBuffer: String, previous: InputState, client: Any?
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        client.setMarkedText(
            composingBuffer, selectionRange: NSMakeRange(composingBuffer.utf16.count, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
    }

    private func handleStateWithSimpleCandidateWindow(
        state: InputState, previous: InputState, client: Any?
    ) {
        gCurrentCandidateController?.visible = false
        hideTooltip()

        guard let client = client as? IMKTextInput else {
            return
        }

        if let previous = previous as? InputState.NotEmpty {
            commit(text: previous.composingBuffer, client: client)
        }
        // the selection range is where the cursor is, with the length being 0 and replacement range NSNotFound,
        // i.e. the client app needs to take care of where to put this composing buffer
        client.setMarkedText(
            "", selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        show(candidateWindowWith: state, client: client)
    }

    private func show(candidateWindowWith state: InputState, client: Any!) {
        let useVerticalMode: Bool = {
            var useVerticalMode = false
            var candidates: [InputState.Candidate] = []
            switch state {
            case let state as InputState.ChoosingCandidate:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case let state as InputState.AssociatedPhrasesPlain:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case let state as InputState.AssociatedPhrases:
                useVerticalMode = state.useVerticalMode
                candidates = state.candidates
            case is InputState.SelectingFeature,
                is InputState.SelectingDateMacro,
                is InputState.SelectingDictionary,
                is InputState.ShowingCharInfo,
                is InputState.Number,
                is InputState.IcuTransform:
                return true
            default:
                break
            }

            if useVerticalMode == true {
                return true
            }
            candidates.sort {
                return $0.displayText.count > $1.displayText.count
            }
            // If there is a candidate which is too long, we use the vertical
            // candidate list window automatically.
            if candidates.first?.displayText.count ?? 0 > 8 {
                return true
            }
            return false
        }()

        gCurrentCandidateController?.delegate = nil
        gCurrentCandidateController?.visible = false

        if useVerticalMode {
            gCurrentCandidateController = .vertical
        } else if Preferences.useHorizontalCandidateList {
            gCurrentCandidateController = .horizontal
        } else {
            gCurrentCandidateController = .vertical
        }

        gCurrentCandidateController?.tooltip =
            switch state {
            case let state as InputState.SelectingDictionary:
                String(format: NSLocalizedString("Look up %@", comment: ""), state.selectedPhrase)
            case let state as InputState.AssociatedPhrases:
                String(format: NSLocalizedString("%@…", comment: ""), state.prefixValue)
            case let state as InputState.CustomMenu:
                state.title
            default:
                ""
            }

        // set the attributes for the candidate panel (which uses NSAttributedString)
        let textSize = Preferences.candidateListTextSize
        let keyLabelSize = max(textSize / 2, kMinKeyLabelSize)

        func font(name: String?, size: CGFloat) -> NSFont {
            if let name = name {
                return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
            }
            return NSFont.systemFont(ofSize: size)
        }

        gCurrentCandidateController?.keyLabelFont = font(
            name: Preferences.candidateKeyLabelFontName, size: keyLabelSize)
        gCurrentCandidateController?.candidateFont = font(
            name: Preferences.candidateTextFontName, size: textSize)

        let candidateKeys = Preferences.candidateKeys
        let keyLabels =
            candidateKeys.count >= 4
            ? Array(candidateKeys) : Array(Preferences.defaultCandidateKeys)

        let keyLabelFormat: (String)->String = switch state {
        case let state as InputState.AssociatedPhrases where state.autoTriggered:
            { _ in "⇧ ⏎" }
        case is InputState.AssociatedPhrasesPlain,
            is InputState.Number,
            is InputState.IcuTransform:
            { "⇧ " + $0 }
        default:
            { $0 }
        }
        gCurrentCandidateController?.keyLabels = keyLabels.map {
            CandidateKeyLabel(key: String($0), displayedText: keyLabelFormat(String($0)))
        }

        gCurrentCandidateController?.delegate = self
        gCurrentCandidateController?.reloadData()
        currentClient = client

        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        var cursor: Int = 0

        if let state = state as? InputState.NotEmpty {
            cursor = Int(state.cursorIndex)
            if cursor == state.composingBuffer.count && cursor != 0 {
                cursor -= 1
            }
        }

        while lineHeightRect.origin.x == 0 && lineHeightRect.origin.y == 0 && cursor >= 0 {
            (client as? IMKTextInput)?.attributes(
                forCharacterIndex: cursor, lineHeightRectangle: &lineHeightRect)
            cursor -= 1
        }

        if useVerticalMode {
            gCurrentCandidateController?.set(
                windowTopLeftPoint: NSMakePoint(
                    lineHeightRect.origin.x + lineHeightRect.size.width + 4.0,
                    lineHeightRect.origin.y - 4.0),
                bottomOutOfScreenAdjustmentHeight: lineHeightRect.size.height + 4.0)
        } else {
            gCurrentCandidateController?.set(
                windowTopLeftPoint: NSMakePoint(
                    lineHeightRect.origin.x, lineHeightRect.origin.y - 4.0),
                bottomOutOfScreenAdjustmentHeight: lineHeightRect.size.height + 4.0)
        }

        gCurrentCandidateController?.visible = true
    }

    private func show(tooltip: String, composingBuffer: String, cursorIndex: UInt, client: Any!) {
        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        var cursor: Int = Int(cursorIndex)
        if cursor == composingBuffer.count && cursor != 0 {
            cursor -= 1
        }

        var isVerticalMode = false
        while lineHeightRect.origin.x == 0 && lineHeightRect.origin.y == 0 && cursor >= 0 {
            let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(
                forCharacterIndex: cursor, lineHeightRectangle: &lineHeightRect)
            let useVerticalMode =
                (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false
            isVerticalMode = isVerticalMode || useVerticalMode
            cursor -= 1
        }

        // Make sure that tooltip hovers next to the vertical text.
        if isVerticalMode && lineHeightRect.size.height > 0 {
            lineHeightRect.origin.x += (lineHeightRect.size.width + 1.0)
        }

        McBopomofoInputMethodController.tooltipController.show(
            tooltip: tooltip, at: lineHeightRect.origin)
    }

    private func hideTooltip() {
        McBopomofoInputMethodController.tooltipController.hide()
    }

    private func checkUserFileIssues() {
        let issues: [String] = keyHandler.collectUserFileIssues()

        // McBopomofoLM caps the maximum number of issues collected, and so
        // we'll just do this O(n) comparison since n is small.
        if McBopomofoInputMethodController.latestUserFileIssues != issues {
            McBopomofoInputMethodController.latestUserFileIssues = issues

            if !McBopomofoInputMethodController.latestUserFileIssues.isEmpty {
                NotifierController.notify(
                    message: NSLocalizedString(
                        "Check McBopomofo menu for user file issues", comment: ""), stay: true)
            }
        }
    }

    // MARK: - gg 輸入法 (公司: wtf) - 中英混打雙軌引擎

    private func showTooltipForMixedInput(_ tooltip: String, client: Any!) {
        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        (client as? IMKTextInput)?.attributes(
            forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)
        if lineHeightRect.origin.x != 0 || lineHeightRect.origin.y != 0 {
            McBopomofoInputMethodController.tooltipController.show(
                tooltip: tooltip, at: NSMakePoint(lineHeightRect.origin.x, lineHeightRect.origin.y - 4.0))
        } else {
            McBopomofoInputMethodController.tooltipController.show(
                tooltip: tooltip, at: NSEvent.mouseLocation)
        }
    }

    private func handleWTFMixedInput(event: NSEvent, client: Any!) -> Bool? {
        guard event.type == .keyDown else { return nil }

        // Caps Lock 鎖定大寫時，交由注音引擎/原生直接輸出英文字母與數字，避開雙軌組字與浮動提示
        if event.modifierFlags.contains(.capsLock) {
            if !WTFMixedInputManager.shared.currentBuffer.isEmpty || WTFMixedInputManager.shared.isPureEnglishMode {
                WTFMixedInputManager.shared.clear()
                hideTooltip()
            }
            return nil
        }

        // 忽略包含 Command 或 Control 的快捷組合鍵
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            if !WTFMixedInputManager.shared.currentBuffer.isEmpty || WTFMixedInputManager.shared.isPureEnglishMode {
                WTFMixedInputManager.shared.clear()
                hideTooltip()
            }
            return nil
        }

        // 候選字窗展開中時，不干預選字邏輯
        let isCandidateWindowVisible = (gCurrentCandidateController?.visible == true) || (state is InputState.ChoosingCandidate)
        if isCandidateWindowVisible {
            return nil
        }

        let keyCode = event.keyCode
        let kTab: UInt16 = 48
        let kReturn: UInt16 = 36
        let kEnterNumPad: UInt16 = 76
        let kSpace: UInt16 = 49
        let kDelete: UInt16 = 51
        let kEscape: UInt16 = 53

        // 若有未處理的中文聯想字，只要按的不是 Tab，立刻清除並關閉提示 (對齊開發書第 7 章)
        if keyCode != kTab && WTFMixedInputManager.shared.associatedSuggestion != nil {
            WTFMixedInputManager.shared.associatedSuggestion = nil
            if WTFMixedInputManager.shared.currentBuffer.isEmpty {
                hideTooltip()
            }
        }

        // Option 鍵字面輸出 (對齊開發書第 9.7 節：按住 Option + 數字/標點直接輸出字面字元，免切換英文)
        if event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
            var literalChar: String? = nil
            let isShift = event.modifierFlags.contains(.shift)

            switch keyCode {
            case 18: literalChar = isShift ? "!" : "1"
            case 19: literalChar = isShift ? "@" : "2"
            case 20: literalChar = isShift ? "#" : "3"
            case 21: literalChar = isShift ? "$" : "4"
            case 23: literalChar = isShift ? "%" : "5"
            case 22: literalChar = isShift ? "^" : "6"
            case 26: literalChar = isShift ? "&" : "7"
            case 28: literalChar = isShift ? "*" : "8"
            case 25: literalChar = isShift ? "(" : "9"
            case 29: literalChar = isShift ? ")" : "0"
            case 43: literalChar = isShift ? "<" : ","
            case 47: literalChar = isShift ? ">" : "."
            case 27: literalChar = isShift ? "_" : "-"
            case 24: literalChar = isShift ? "+" : "="
            default: break
            }

            if let literal = literalChar {
                if WTFMixedInputManager.shared.isPureEnglishMode {
                    let buf = WTFMixedInputManager.shared.currentBuffer
                    if !buf.isEmpty { commit(text: buf, isEnglish: true, client: client) }
                }
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                WTFMixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))

                commit(text: literal, isEnglish: true, client: client)
                hideTooltip()
                return true
            }
        }

        // 1. 純英文模式 (Pure English Mode)
        if WTFMixedInputManager.shared.isPureEnglishMode {
            // Backspace: 逐字刪除英文
            if keyCode == kDelete {
                WTFMixedInputManager.shared.removeLastKey()
                if WTFMixedInputManager.shared.currentBuffer.isEmpty {
                    WTFMixedInputManager.shared.clear()
                    (client as? IMKTextInput)?.setMarkedText(
                        "", selectionRange: NSRange(location: 0, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    hideTooltip()
                } else {
                    let buf = WTFMixedInputManager.shared.currentBuffer
                    (client as? IMKTextInput)?.setMarkedText(
                        buf, selectionRange: NSRange(location: buf.count, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    if let tip = WTFMixedInputManager.shared.tooltipDisplay {
                        showTooltipForMixedInput(tip, client: client)
                    } else {
                        hideTooltip()
                    }
                }
                return true
            }

            // Escape: 取消整段輸入
            if keyCode == kEscape {
                WTFMixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            }

            // Space: 送出英文字 + 空白
            if keyCode == kSpace {
                let word = WTFMixedInputManager.shared.currentBuffer + " "
                commit(text: word, isEnglish: true, client: client)
                WTFMixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            }

            // Return / Enter: 送出英文字 (無空格)
            if keyCode == kReturn || keyCode == kEnterNumPad {
                let word = WTFMixedInputManager.shared.currentBuffer
                commit(text: word, isEnglish: true, client: client)
                WTFMixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            }

            // Tab: 接受英文預測詞補全並送出
            if keyCode == kTab {
                let targetWord = WTFMixedInputManager.shared.predictedWord ?? WTFMixedInputManager.shared.currentBuffer
                commit(text: targetWord, isEnglish: true, client: client)
                WTFMixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            }

            // 在純英文模式下的字母輸入
            if let chars = event.characters, let first = chars.first, first.isASCII, !first.isWhitespace {
                WTFMixedInputManager.shared.appendKey(first)
                let buf = WTFMixedInputManager.shared.currentBuffer
                (client as? IMKTextInput)?.setMarkedText(
                    buf, selectionRange: NSRange(location: buf.count, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                if let tip = WTFMixedInputManager.shared.tooltipDisplay {
                    showTooltipForMixedInput(tip, client: client)
                } else {
                    hideTooltip()
                }
                return true
            }
            return nil
        }

        // 2. 雙軌狀態 (尚未鎖定純英文)
        // Tab 鍵：送出整句（若有英文預測詞則補全英文後送出；若有中文聯想字則一鍵補全中文）
        if keyCode == kTab && !isCandidateWindowVisible {
            if let word = WTFMixedInputManager.shared.predictedWord, !word.isEmpty {
                // 如果前面有未確定的中文，先強制送出中文！
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                commit(text: word, isEnglish: true, client: client)
                WTFMixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            } else if (state is InputState.Inputting) || !WTFMixedInputManager.shared.currentBuffer.isEmpty {
                // 中文或雙軌組字狀態下，Tab 直接確認並送出整句！
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                WTFMixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            } else if let suggestion = WTFMixedInputManager.shared.associatedSuggestion, !suggestion.isEmpty {
                // 中文聯想字：Tab 一鍵補全接續字！ (對齊開發書第 7 章)
                commit(text: suggestion, isEnglish: false, client: client)
                WTFMixedInputManager.shared.associatedSuggestion = nil
                hideTooltip()
                return true
            }
            return nil
        }

        // 3. ← → 以外的方向鍵與翻頁鍵：送出整句
        // Page Up (116), Page Down (121), Home (115), End (119)
        if (keyCode == 116 || keyCode == 121 || keyCode == 115 || keyCode == 119) && !isCandidateWindowVisible {
            if (state is InputState.Inputting) || WTFMixedInputManager.shared.isPureEnglishMode {
                if WTFMixedInputManager.shared.isPureEnglishMode {
                    let buf = WTFMixedInputManager.shared.currentBuffer
                    if !buf.isEmpty { commit(text: buf, isEnglish: true, client: client) }
                }
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                WTFMixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return false // 讓翻頁鍵繼續在文件中生效
            }
        }

        // Backspace 鍵：同步縮減英文緩衝區，但絕不攔截，交由注音引擎/macOS原生處理刪除！
        if keyCode == kDelete {
            if !WTFMixedInputManager.shared.currentBuffer.isEmpty {
                WTFMixedInputManager.shared.removeLastKey()
                if WTFMixedInputManager.shared.currentBuffer.isEmpty {
                    hideTooltip()
                } else if let tip = WTFMixedInputManager.shared.tooltipDisplay {
                    showTooltipForMixedInput(tip, client: client)
                }
            }
            // 返回 nil，確保 KeyHandler 或 macOS 收到 Delete 鍵，刪除完全順暢無阻！
            return nil
        }

        // 字母輸入判斷
        if let chars = event.characters, let first = chars.first {
            // 只有 ASCII 英文字母 (a-z, A-Z) 參與雙軌預測
            if (first >= "a" && first <= "z") || (first >= "A" && first <= "Z") {
                let testBuffer = WTFMixedInputManager.shared.currentBuffer + String(first)
                let isValidBpmf = WTFMixedInputManager.shared.validateBopomofo(input: testBuffer).isValid
                let isMultiBpmf = WTFMixedInputManager.shared.validateMultiSyllableBopomofo(input: testBuffer)
                let prediction = WTFMixedInputManager.shared.predictEnglish(prefix: testBuffer)

                let isExplicitUpper = first.isUppercase
                let isInvalidBpmf = !isValidBpmf && !isMultiBpmf && (prediction != nil || testBuffer.count >= 2)

                if isExplicitUpper || isInvalidBpmf {
                    // 非法注音音節或大寫字母：切入純英文模式！
                    // 【關鍵修正】：必須先將 isPureEnglishMode 設為 true，並把完整英文字串 (testBuffer) 存好！
                    // 這樣隨後呼叫 handleForceCommit 觸發 handle(state: Committing) 時，才不會因 !isPureEnglishMode 誤清空英文緩衝區！
                    WTFMixedInputManager.shared.isPureEnglishMode = true
                    WTFMixedInputManager.shared.currentBuffer = testBuffer
                    WTFMixedInputManager.shared.predictedWord = prediction

                    // 強制送出前面尚未確定/排隊中的中文詞彙 (例如「今天」)
                    keyHandler.handleForceCommit { [weak self] commitState in
                        self?.handle(state: commitState, client: client)
                    }

                    keyHandler.clear()
                    self.state = InputState.Empty()

                    // Live Pangu spacing right before the English marked text when switching from Chinese
                    if WTFMixedInputManager.shared.panguSpacingEnabled,
                       let prev = WTFMixedInputManager.shared.lastCommittedChar,
                       let firstEng = testBuffer.first,
                       WTFMixedInputManager.needsPanguSpace(left: prev, right: firstEng) {
                        (client as? IMKTextInput)?.insertText(
                            " ", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                        WTFMixedInputManager.shared.lastCommittedChar = " "
                        WTFMixedInputManager.shared.lastCommitWasEnglishWord = false
                    }

                    let buf = WTFMixedInputManager.shared.currentBuffer
                    (client as? IMKTextInput)?.setMarkedText(
                        buf, selectionRange: NSRange(location: buf.count, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    if let tip = WTFMixedInputManager.shared.tooltipDisplay {
                        showTooltipForMixedInput(tip, client: client)
                    } else {
                        hideTooltip()
                    }
                    return true
                }
            } else {
                // 輸入非字母鍵（數字、標點、符號等）：必定屬於中文注音流程，清空英文緩衝區！
                if !WTFMixedInputManager.shared.currentBuffer.isEmpty {
                    WTFMixedInputManager.shared.clear()
                    hideTooltip()
                }
            }
        }

        return nil
    }

    private func postProcessWTFMixedInput(event: NSEvent, client: Any!) {
        guard event.type == .keyDown else { return }
        if event.modifierFlags.contains(.capsLock) {
            return
        }
        let keyCode = event.keyCode

        // 全形句末標點 。 ！ ？ 送出整句（含標點）
        if let inputting = self.state as? InputState.Inputting {
            let buf = inputting.composingBuffer
            if buf.hasSuffix("。") || buf.hasSuffix("！") || buf.hasSuffix("？") {
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                self.handle(state: InputState.Empty(), client: client)
                WTFMixedInputManager.shared.clear()
                hideTooltip()
                return
            }
        }

        // 空白、Enter、Escape 代表段落完成，清空狀態
        if keyCode == 49 || keyCode == 36 || keyCode == 76 || keyCode == 53 {
            WTFMixedInputManager.shared.clear()
            hideTooltip()
            return
        }

        if let chars = event.characters, let first = chars.first {
            // 聲調鍵 (3, 4, 6, 7) 代表注音完成
            if first == "3" || first == "4" || first == "6" || first == "7" {
                WTFMixedInputManager.shared.clear()
                hideTooltip()
                return
            }

            // 只有英文字母才累加進緩衝區
            if (first >= "a" && first <= "z") || (first >= "A" && first <= "Z") {
                WTFMixedInputManager.shared.appendKey(first)
                if let tip = WTFMixedInputManager.shared.tooltipDisplay {
                    showTooltipForMixedInput(tip, client: client)
                } else {
                    hideTooltip()
                }
            } else {
                WTFMixedInputManager.shared.clear()
                hideTooltip()
            }
        }
    }
}
