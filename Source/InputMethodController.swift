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
    static let grid = GridCandidateController()
}

@objc(McBopomofoInputMethodController)
class McBopomofoInputMethodController: IMKInputController {

    private static let tooltipController = TooltipController()

    // MARK: -

    var currentClient: Any?
    var keyHandler: KeyHandler = KeyHandler()
    var state: InputState = InputState.Empty()
    private var isVerticalMode: Bool = false

    // Share the stored issues, so a set of issues is shown as notification only once.
    static var latestUserFileIssues: [String] = []

    private func effectiveKeyboardLayout(named layoutName: String) -> String {
        if InputSourceHelper.inputSource(for: layoutName) != nil {
            return layoutName
        }
        if InputSourceHelper.inputSource(for: "com.apple.keylayout.ABC") != nil {
            return "com.apple.keylayout.ABC"
        }
        return layoutName
    }

    // MARK: - IMKInputController methods

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        keyHandler.delegate = self
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Input Method Menu")

        let chineseConversionItem = menu.addItem(
            withTitle: NSLocalizedString("Convert to Simplified Chinese", comment: ""),
            action: #selector(toggleChineseConverter(_:)), keyEquivalent: "g")
        chineseConversionItem.keyEquivalentModifierMask = [.command, .control]
        chineseConversionItem.state = Preferences.chineseConversionEnabled.state
        chineseConversionItem.target = self

        let halfWidthPunctuationItem = menu.addItem(
            withTitle: NSLocalizedString("Use Half-Width Punctuations", comment: ""),
            action: #selector(toggleHalfWidthPunctuation(_:)), keyEquivalent: "h")
        halfWidthPunctuationItem.keyEquivalentModifierMask = [.command, .control]
        halfWidthPunctuationItem.state = Preferences.halfWidthPunctuationEnabled.state
        halfWidthPunctuationItem.target = self

        menu.addItem(NSMenuItem.separator())

        let prefItem = menu.addItem(
            withTitle: NSLocalizedString("McBopomofo Preferences", comment: ""),
            action: #selector(showPreferences(_:)), keyEquivalent: "")
        prefItem.target = self

        menu.addItem(NSMenuItem.separator())

        let uninstallItem = menu.addItem(
            withTitle: NSLocalizedString("Uninstall gg…", comment: ""),
            action: #selector(uninstallGG(_:)), keyEquivalent: "")
        uninstallItem.target = self
        return menu
    }

    // MARK: - IMKStateSetting protocol methods

    override func activateServer(_ client: Any!) {
        LanguageModelManager.loadDataModel(keyHandler.inputMode)
        isVerticalMode = false

        // Override the keyboard layout with dynamic fallback.
        let effectiveLayout = effectiveKeyboardLayout(named: Preferences.basisKeyboardLayout)
        (client as? IMKTextInput)?.overrideKeyboard(
            withKeyboardNamed: effectiveLayout)
        // reset the state
        currentClient = client

        MixedInputManager.shared.clear()
        MixedInputManager.shared.resetCommittedContext()
        keyHandler.clear()
        keyHandler.syncWithPreferences()
        self.state = InputState.Empty()
    }

    override func deactivateServer(_ client: Any!) {
        currentClient = nil
        MixedInputManager.shared.clear()
        hideTooltip()
        LanguageModelManager.userOverrideModel.saveImmediately()
        keyHandler.clear()
        self.handle(state: .Deactivated(), client: client)
        MixedInputManager.shared.resetCommittedContext()
    }

    override func setValue(_ value: Any!, forTag tag: Int, client: Any!) {
        let newInputMode = InputMode(rawValue: value as? String ?? InputMode.bopomofo.rawValue)
        LanguageModelManager.loadDataModel(newInputMode)
        // Restore the client layout even when the internal input mode is unchanged.
        let effectiveLayout = effectiveKeyboardLayout(named: Preferences.basisKeyboardLayout)
        (client as? IMKTextInput)?.overrideKeyboard(
            withKeyboardNamed: effectiveLayout)
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
        if MixedInputManager.shared.isPureEnglishMode {
            let buf = MixedInputManager.shared.currentBuffer
            if !buf.isEmpty {
                commit(text: buf, isEnglish: true, client: client)
            }
        }
        MixedInputManager.shared.clear()
        hideTooltip()
        keyHandler.handleForceCommit(stateCallback: { newState in
            self.handle(state: newState, client: client)
        })
        MixedInputManager.shared.resetCommittedContext()
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
            if (state is InputState.Empty) && !MixedInputManager.shared.isPureEnglishMode {
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
            let functionKeyKeyboardLayoutID = effectiveKeyboardLayout(named: Preferences.functionKeyboardLayout)
            let basisKeyboardLayoutID = effectiveKeyboardLayout(named: Preferences.basisKeyboardLayout)

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

        // 中英混打雙軌模組攔截
        if MixedInputManager.shared.isEnabled {
            if let handled = handleMixedInput(event: event, client: client) {
                return handled
            }
        }

        if event.keyCode >= 123 && event.keyCode <= 126 {
            var textFrame = NSRect.zero
            let attributes: [AnyHashable: Any]? = (client as? IMKTextInput)?.attributes(
                forCharacterIndex: 0, lineHeightRectangle: &textFrame)
            isVerticalMode =
                (attributes?["IMKTextOrientation"] as? NSNumber)?.intValue == 0 || false
        }
        if let textInput = client as? IMKTextInput {
            keyHandler.clientBundleID = textInput.bundleIdentifier()
        }
        let input = KeyHandlerInput(event: event, isVerticalMode: isVerticalMode)

        let result = keyHandler.handle(input: input, state: state) { newState in
            self.handle(state: newState, client: client)
        } errorCallback: {
            if Preferences.beepUponInputError {
                NSSound.beep()
            }
        }

        if result, MixedInputManager.shared.isEnabled, event.type == .keyDown {
            postProcessMixedInput(event: event, client: client)
        } else if !result, event.type == .keyDown {
            let keyCode = event.keyCode
            // Backspace, Return, Enter, Tab, Forward Delete, Home/End/PageUp/PageDown, or arrow keys when buffer is empty: reset committed context
            if keyCode == 51 || keyCode == 36 || keyCode == 76 || keyCode == 48 || keyCode == 117 || keyCode == 115 || keyCode == 119 || keyCode == 116 || keyCode == 121 || (keyCode >= 123 && keyCode <= 126) {
                MixedInputManager.shared.resetCommittedContext()
            } else if !event.modifierFlags.intersection([.command, .control]).isEmpty {
                // Command / Control shortcuts (e.g. Cmd+V, Cmd+Z, Cmd+A, Cmd+C) invalidate last committed context
                MixedInputManager.shared.resetCommittedContext()
            } else if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      let chars = event.characters, !chars.isEmpty,
                      let first = chars.first, first.isASCII, !first.isNewline,
                      first >= " " && first <= "~" {
                let clientBundleID = (client as? IMKTextInput)?.bundleIdentifier()
                let clientContext = characterPrecedingCursor(from: client)
                let precedingChar = clientContext.hasClientContext ? clientContext.char : MixedInputManager.shared.lastCommittedChar
                // Direct pass-through ASCII input (e.g. CapsLock English mode or unconsumed numbers/symbols)
                if MixedInputManager.shared.panguSpacingEnabled,
                   !MixedInputManager.isPanguExcludedApp(bundleID: clientBundleID),
                   let prev = precedingChar,
                   MixedInputManager.needsPanguSpace(left: prev, right: first) {
                    commit(text: chars, isEnglish: true, client: client)
                    return true
                }
                MixedInputManager.shared.lastCommittedChar = chars.last
                MixedInputManager.shared.lastCommitWasEnglishWord = MixedInputManager.isASCIIAlphanumeric(first)
            }
        }

        return result
    }

    // MARK: - Menu Items

    @objc override func showPreferences(_ sender: Any?) {
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.showPreferences()
        }
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

    @objc func uninstallGG(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.uninstallGG()
    }
}

// MARK: - State Handling

extension McBopomofoInputMethodController {

    func handle(state newState: InputState, client: Any?) {
        let previous = state
        state = newState

        switch newState {
        case let newState as InputState.Deactivated:
            MixedInputManager.shared.clear()
            MixedInputManager.shared.resetCommittedContext()
            hideTooltip()
            handle(state: newState, previous: previous, client: client)
            state = .Empty()
        case let newState as InputState.SwitchingInputSource:
            MixedInputManager.shared.clear()
            MixedInputManager.shared.resetCommittedContext()
            hideTooltip()
            handle(state: newState, previous: previous, client: client)
            state = .Empty()
            if !InputSourceHelper.selectInputSource(withID: newState.sourceID) {
                NSLog("Unable to switch to input source: %@", newState.sourceID)
            }
        case let newState as InputState.Empty:
            if !MixedInputManager.shared.isPureEnglishMode {
                MixedInputManager.shared.clear()
                hideTooltip()
            }
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.EmptyIgnoringPreviousState:
            if !MixedInputManager.shared.isPureEnglishMode {
                MixedInputManager.shared.clear()
                hideTooltip()
            }
            handle(state: newState, previous: previous, client: client)
        case let newState as InputState.Committing:
            if !MixedInputManager.shared.isPureEnglishMode {
                MixedInputManager.shared.clear()
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

    private func characterPrecedingCursor(from client: Any?) -> (char: Character?, hasClientContext: Bool) {
        guard let textInput = client as? IMKTextInput else { return (nil, false) }
        let sel = textInput.selectedRange()
        guard sel.location != NSNotFound else { return (nil, false) }
        if sel.location == 0 {
            return (nil, true)
        }
        let readLen = min(sel.location, 4)
        let range = NSRange(location: sel.location - readLen, length: readLen)
        if let attrStr = textInput.attributedSubstring(from: range), !attrStr.string.isEmpty {
            return (attrStr.string.last, true)
        }
        return (nil, false)
    }

    private func commit(text: String, isEnglish: Bool = false, client: Any!) {

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
        let clientBundleID = (client as? IMKTextInput)?.bundleIdentifier()
        let clientContext = characterPrecedingCursor(from: client)
        let precedingChar = clientContext.hasClientContext ? clientContext.char : MixedInputManager.shared.lastCommittedChar
        buffer = MixedInputManager.shared.applyPanguSpacing(
            to: buffer,
            isEnglishWord: isEnglish && buffer.count > 1 && !buffer.hasSuffix(" "),
            precedingChar: precedingChar,
            clientBundleID: clientBundleID
        )

        (client as? IMKTextInput)?.insertText(
            buffer, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
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
            commit(text: poppedText, client: client)
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

        let effectiveState = state

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
            if candidates.contains(where: { $0.displayText.count > 8 }) {
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
        } else if Preferences.useGridCandidateList {
            gCurrentCandidateController = .grid
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

    // MARK: - gg 輸入法 - 中英混打雙軌引擎

    private func showTooltipForMixedInput(_ tooltip: String, client: Any!) {
        // 安全密碼輸入模式啟用時，嚴禁顯示任何浮動預測提詞視窗
        if IsSecureEventInputEnabled() {
            hideTooltip()
            return
        }

        // 終端機與程式碼編輯器環境抑制雙軌浮動提詞，防止終端機 sudo 密碼或指令前綴外洩
        let bundleID = (client as? IMKTextInput)?.bundleIdentifier()
        if MixedInputManager.isPanguExcludedApp(bundleID: bundleID) {
            hideTooltip()
            return
        }

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

    private func handleMixedInput(event: NSEvent, client: Any!) -> Bool? {
        guard event.type == .keyDown else { return nil }

        // Caps Lock 鎖定大寫時，交由注音引擎/原生直接輸出英文字母與數字，避開雙軌組字與浮動提示
        if event.modifierFlags.contains(.capsLock) {
            if !MixedInputManager.shared.currentBuffer.isEmpty || MixedInputManager.shared.isPureEnglishMode {
                MixedInputManager.shared.clear()
                hideTooltip()
            }
            return nil
        }

        // 忽略包含 Command 或 Control 的快捷組合鍵，並同步重置盤古空格上下文（處理 Cmd+C, Cmd+V, Cmd+Z）
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            MixedInputManager.shared.resetCommittedContext()
            if !MixedInputManager.shared.currentBuffer.isEmpty || MixedInputManager.shared.isPureEnglishMode {
                MixedInputManager.shared.clear()
                hideTooltip()
            }
            return nil
        }

        // 候選字窗展開中時，不干預選字邏輯
        let isCandidateWindowVisible = (gCurrentCandidateController?.visible == true) || (state is InputState.ChoosingCandidate)
        if isCandidateWindowVisible {
            return nil
        }

        // 特殊輸入狀態（如 Big5 內碼輸入、標記選詞、中文數字、ICU 轉換、選單等）交由 KeyHandler，不干預
        if state is InputState.Big5 ||
            state is InputState.Marking ||
            state is InputState.Number ||
            state is InputState.IcuTransform ||
            state is InputState.SelectingFeature ||
            state is InputState.SelectingDateMacro ||
            state is InputState.SelectingDictionary ||
            state is InputState.ShowingCharInfo ||
            state is InputState.CustomMenu {
            return nil
        }

        let keyCode = event.keyCode
        let kTab: UInt16 = 48
        let kReturn: UInt16 = 36
        let kEnterNumPad: UInt16 = 76
        let kSpace: UInt16 = 49
        let kDelete: UInt16 = 51
        let kEscape: UInt16 = 53

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
            case 42: literalChar = isShift ? "|" : "\\" 
            case 44: literalChar = isShift ? "?" : "/"
            case 33: literalChar = isShift ? "{" : "["
            case 30: literalChar = isShift ? "}" : "]"
            case 41: literalChar = isShift ? ":" : ";"
            case 39: literalChar = isShift ? "\"" : "'"
            case 50: literalChar = isShift ? "~" : "`"
            default: break
            }

            if let literal = literalChar {
                if MixedInputManager.shared.isPureEnglishMode {
                    let buf = MixedInputManager.shared.currentBuffer
                    if !buf.isEmpty { commit(text: buf, isEnglish: true, client: client) }
                }
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                MixedInputManager.shared.clear()
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
        if MixedInputManager.shared.isPureEnglishMode {
            // Backspace: 逐字刪除英文
            let isDeleteOrBackSpace = (keyCode == kDelete || event.characters?.first == "\u{8}" || event.characters?.first == "\u{7f}")
            if isDeleteOrBackSpace {
                MixedInputManager.shared.removeLastKey()
                if MixedInputManager.shared.currentBuffer.isEmpty {
                    MixedInputManager.shared.clear()
                    self.state = InputState.Empty()
                    (client as? IMKTextInput)?.setMarkedText(
                        "", selectionRange: NSRange(location: 0, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    hideTooltip()
                } else {
                    let buf = MixedInputManager.shared.currentBuffer
                    let displayBuf = MixedInputManager.resolveCommittedEnglish(buf)
                    (client as? IMKTextInput)?.setMarkedText(
                        displayBuf, selectionRange: NSRange(location: displayBuf.count, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    if let tip = MixedInputManager.shared.tooltipDisplay {
                        showTooltipForMixedInput(tip, client: client)
                    } else {
                        hideTooltip()
                    }
                }
                return true
            }

            // Escape: 取消整段輸入
            if keyCode == kEscape {
                MixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            }

            // Space: 送出英文字
            if keyCode == kSpace {
                let buf = MixedInputManager.shared.currentBuffer
                let resolved = MixedInputManager.resolveCommittedEnglish(buf)
                let word = MixedInputManager.isShortTokenOrAcronym(buf) ? resolved : (resolved + " ")
                commit(text: word, isEnglish: true, client: client)
                MixedInputManager.shared.clear()
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
                let buf = MixedInputManager.shared.currentBuffer
                let word = MixedInputManager.resolveCommittedEnglish(buf)
                commit(text: word, isEnglish: true, client: client)
                MixedInputManager.shared.clear()
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
                let buf = MixedInputManager.shared.currentBuffer
                let resolved = MixedInputManager.resolveCommittedEnglish(buf)
                let targetWord = MixedInputManager.shared.predictedWord ?? resolved
                commit(text: targetWord, isEnglish: true, client: client)
                MixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            }

            // 在純英文模式下的字母與數字輸入 (ASCII Alphanumeric)
            if let chars = event.characters, let first = chars.first, MixedInputManager.isASCIIAlphanumeric(first) {
                MixedInputManager.shared.appendKey(first)
                let buf = MixedInputManager.shared.currentBuffer
                let displayBuf = MixedInputManager.resolveCommittedEnglish(buf)
                (client as? IMKTextInput)?.setMarkedText(
                    displayBuf, selectionRange: NSRange(location: displayBuf.count, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                if let tip = MixedInputManager.shared.tooltipDisplay {
                    showTooltipForMixedInput(tip, client: client)
                } else {
                    hideTooltip()
                }
                return true
            }
            return nil
        }

        // 2. 雙軌狀態 (尚未鎖定純英文)
        // Space 鍵：非純英文模式下，Space 代表中文第一聲或選字確認！
        // 立即清空雙軌英文緩衝區，原封不動放行給 KeyHandler.mm，嚴禁插入半形空格！
        if keyCode == kSpace {
            MixedInputManager.shared.clear()
            hideTooltip()
            return nil
        }

        // Tab 鍵：送出整句（若有英文預測詞則補全英文後送出；若有中文聯想字則一鍵補全中文）
        if keyCode == kTab && !isCandidateWindowVisible {
            let current = MixedInputManager.shared.currentBuffer
            let resolved = MixedInputManager.resolveCommittedEnglish(current)
            let predicted = MixedInputManager.shared.predictedWord ?? (MixedInputManager.knownSpecAcronyms[current.lowercased()] != nil ? resolved : nil)
            if let word = predicted, !word.isEmpty {
                // 如果前面有未確定的中文，先強制送出中文！
                keyHandler.clearUnconfirmedReading()
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                commit(text: word, isEnglish: true, client: client)
                MixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            } else if (state is InputState.Inputting) || !MixedInputManager.shared.currentBuffer.isEmpty {
                // 中文或雙軌組字狀態下，Tab 直接確認並送出整句！
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                MixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return true
            }
            return nil
        }

        // 3. ← → 以外的方向鍵與翻頁鍵：送出整句
        // Page Up (116), Page Down (121), Home (115), End (119)
        if (keyCode == 116 || keyCode == 121 || keyCode == 115 || keyCode == 119) && !isCandidateWindowVisible {
            if (state is InputState.Inputting) || MixedInputManager.shared.isPureEnglishMode {
                if MixedInputManager.shared.isPureEnglishMode {
                    let buf = MixedInputManager.shared.currentBuffer
                    if !buf.isEmpty { commit(text: buf, isEnglish: true, client: client) }
                }
                keyHandler.handleForceCommit { [weak self] commitState in
                    self?.handle(state: commitState, client: client)
                }
                MixedInputManager.shared.clear()
                keyHandler.clear()
                self.handle(state: InputState.EmptyIgnoringPreviousState(), client: client)
                (client as? IMKTextInput)?.setMarkedText(
                    "", selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                hideTooltip()
                return false // 讓翻頁鍵繼續在文件中生效
            }
        }

        // Backspace：同步退格雙軌緩衝區，並放行交由 KeyHandler 處理注音組字區退格
        let isDeleteOrBackSpace = (keyCode == kDelete || event.characters?.first == "\u{8}" || event.characters?.first == "\u{7f}")
        if isDeleteOrBackSpace {
            MixedInputManager.shared.removeLastKey()
            hideTooltip()
            return nil
        }

        // 字母與數字輸入判斷 (ASCII Alphanumeric)
        if let chars = event.characters, let first = chars.first {
            if MixedInputManager.isASCIIAlphanumeric(first) {
                let current = MixedInputManager.shared.currentBuffer
                let testBuffer = current + String(first)
                let isExplicitUpper = first.isUppercase

                // 檢查是否為合法中文聲調完成 (如 m+4=玉, 1u+4=必, su+3=你)
                if MixedInputManager.toneDigits.contains(first) {
                    if keyHandler.hasUnconfirmedReading() || (!current.isEmpty && MixedInputManager.shared.validateBopomofo(input: testBuffer).isValid) {
                        // 使用者按聲調鍵宣告要中文！清空英文緩衝區，放行給 KeyHandler 組字
                        MixedInputManager.shared.clear()
                        hideTooltip()
                        return nil
                    }
                }

                // 檢查英數混打相衝 (Rule A, Rule B, Rule C)
                let isCollision = MixedInputManager.shared.checkAlphanumericCollision(buffer: current, nextChar: first)

                // 檢查注音合法性（短路求值優化，解決打字卡頓）
                var prediction: String? = nil
                let isValidBpmf = MixedInputManager.shared.validateBopomofo(input: testBuffer).isValid
                let isMultiBpmf = isValidBpmf ? false : MixedInputManager.shared.validateMultiSyllableBopomofo(input: testBuffer)
                let isInvalidBpmf: Bool
                if isValidBpmf || isMultiBpmf {
                    isInvalidBpmf = false
                } else {
                    // 僅當輸入以英文字母開頭且匹配到英文詞預測時，才判定為英文輸入意圖切換模式
                    if let firstChar = testBuffer.first, firstChar.isLetter {
                        prediction = MixedInputManager.shared.predictEnglish(prefix: testBuffer)
                        isInvalidBpmf = (prediction != nil)
                    } else {
                        isInvalidBpmf = false
                    }
                }

                if isExplicitUpper || isCollision || isInvalidBpmf {
                    // 若因大寫或相衝進入英文模式，且尚未預測，則惰性補算
                    if prediction == nil {
                        prediction = MixedInputManager.shared.predictEnglish(prefix: testBuffer)
                    }

                    // 非法注音音節、英數相衝或大寫字母：切入純英文模式！
                    let resolved = MixedInputManager.resolveCommittedEnglish(testBuffer)
                    MixedInputManager.shared.isPureEnglishMode = true
                    MixedInputManager.shared.currentBuffer = testBuffer
                    MixedInputManager.shared.predictedWord = prediction

                    // 順序細節：先清除底層未完成的注音符號 (Reading Buffer 中的 ㄏㄣ)
                    keyHandler.clearUnconfirmedReading()

                    // 再強制送出前面尚未確定/已成形的中文字詞 (如「這台」)
                    keyHandler.handleForceCommit { [weak self] commitState in
                        self?.handle(state: commitState, client: client)
                    }

                    keyHandler.clear()
                    self.state = InputState.Empty()

                    let displayBuf = resolved
                    (client as? IMKTextInput)?.setMarkedText(
                        displayBuf, selectionRange: NSRange(location: displayBuf.count, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    if let tip = MixedInputManager.shared.tooltipDisplay {
                        showTooltipForMixedInput(tip, client: client)
                    } else {
                        hideTooltip()
                    }
                    return true
                }
            } else {
                // 符號是否為注音鍵依 KeyHandler 當前鍵盤佈局判斷；Shift 等修飾鍵不走讀音分流。
                let disqualifyingModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .capsLock]
                let hasDisqualifyingModifiers = !event.modifierFlags.intersection(disqualifyingModifiers).isEmpty
                let hasReading = keyHandler.hasUnconfirmedReading()
                let isLayoutReadingKey = first.isASCII && keyHandler.isValidReadingKey(Int8(bitPattern: first.asciiValue ?? 0))
                if hasReading && isLayoutReadingKey && !hasDisqualifyingModifiers {
                    return nil
                }
                if !MixedInputManager.shared.currentBuffer.isEmpty {
                    MixedInputManager.shared.clear()
                    hideTooltip()
                }
            }
        }

        return nil
    }

    private func postProcessMixedInput(event: NSEvent, client: Any!) {
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
                MixedInputManager.shared.clear()
                hideTooltip()
                return
            }
        }

        // 空白、Enter、Escape 代表段落完成，清空狀態
        if keyCode == 49 || keyCode == 36 || keyCode == 76 || keyCode == 53 {
            MixedInputManager.shared.clear()
            hideTooltip()
            return
        }

        // Backspace: 雙軌模式下同步遞減一個字元
        if keyCode == 51 {
            if !MixedInputManager.shared.currentBuffer.isEmpty {
                MixedInputManager.shared.removeLastKey()
                if let tip = MixedInputManager.shared.tooltipDisplay {
                    showTooltipForMixedInput(tip, client: client)
                } else {
                    hideTooltip()
                }
            }
            return
        }

        if let chars = event.characters, let first = chars.first {
            // 聲調鍵 (3, 4, 6, 7)：
            // 1. 若目前組字區中已有完成的中文字，或者緩衝區原本已有中文前綴完成組字，一律清空，絕不追加！
            // 2. 只有在「組字區為空」且「雙軌緩衝區為空」的純孤立狀態下按下 3, 4, 6, 7，才記錄為孤立聲調 (以防 4K、3D、3C)
            if first == "3" || first == "4" || first == "6" || first == "7" {
                let hasComposedChinese = (self.state as? InputState.NotEmpty)?.composingBuffer.contains(where: { MixedInputManager.isCJK($0) }) ?? false
                let hadPrefix = !MixedInputManager.shared.currentBuffer.isEmpty
                if hasComposedChinese || hadPrefix {
                    MixedInputManager.shared.clear()
                    hideTooltip()
                    return
                }
            }

            // 若目前組字區中已有完成的中文字，且當前已無未完成的注音讀音 (例如剛按完聲調或空白完成了一個中文字)
            // 則清空雙軌緩衝區，為下一個字或下一個英文單字做好準備
            if let notEmpty = self.state as? InputState.NotEmpty,
               notEmpty.composingBuffer.contains(where: { MixedInputManager.isCJK($0) }),
               !keyHandler.hasUnconfirmedReading() {
                MixedInputManager.shared.clear()
                hideTooltip()
                return
            }

            // 英文字母與數字 (0-9) 均累加進緩衝區；合法的符號韻母（; / , . -）若為延續注音讀音亦累加進緩衝區
            let disqualifyingModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .capsLock]
            let hasDisqualifyingModifiers = !event.modifierFlags.intersection(disqualifyingModifiers).isEmpty
            let isLayoutReadingKey = first.isASCII && keyHandler.isValidReadingKey(Int8(bitPattern: first.asciiValue ?? 0))
            let isReadingFinalKey = isLayoutReadingKey && keyHandler.hasUnconfirmedReading() && !hasDisqualifyingModifiers

            if MixedInputManager.isASCIIAlphanumeric(first) || isReadingFinalKey {
                MixedInputManager.shared.appendKey(first)
                if MixedInputManager.shared.isPureEnglishMode, let tip = MixedInputManager.shared.tooltipDisplay {
                    showTooltipForMixedInput(tip, client: client)
                } else {
                    hideTooltip()
                }
            } else {
                MixedInputManager.shared.clear()
                hideTooltip()
            }
        }
    }
}
