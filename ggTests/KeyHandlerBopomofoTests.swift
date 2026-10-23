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
import InputMethodKit
import XCTest

@testable import gg

func charCode(_ string: String) -> UInt16 {
    let scalars = string.unicodeScalars
    return UInt16(scalars[scalars.startIndex].value)
}

class KeyHandlerBopomofoTests: XCTestCase {

    var handler = KeyHandler()
    var savedKeyboardLayout: KeyboardLayout = .standard
    var chineseConversionEnabled: Bool = false
    var savedSwitchInputSourceUponShiftLetterKeyComboEnabled = false

    override func setUpWithError() throws {
        savedKeyboardLayout = Preferences.keyboardLayout
        chineseConversionEnabled = Preferences.chineseConversionEnabled
        savedSwitchInputSourceUponShiftLetterKeyComboEnabled = Preferences.switchInputSourceUponShiftLetterKeyComboEnabled
        Preferences.chineseConversionEnabled = false
        Preferences.keyboardLayout = .standard
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = false
        LanguageModelManager.loadDataModels()
        handler = KeyHandler()
        handler.inputMode = .bopomofo
    }

    override func tearDownWithError() throws {
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = savedSwitchInputSourceUponShiftLetterKeyComboEnabled
        Preferences.chineseConversionEnabled = chineseConversionEnabled
        Preferences.keyboardLayout = savedKeyboardLayout
    }

    func testSyncWithPreferences() {
        let savedKeyboardLayout = Preferences.keyboardLayout
        Preferences.keyboardLayout = .standard
        handler.syncWithPreferences()

        Preferences.keyboardLayout = .eten
        handler.syncWithPreferences()

        Preferences.keyboardLayout = .hsu
        handler.syncWithPreferences()

        Preferences.keyboardLayout = .eten26
        handler.syncWithPreferences()

        Preferences.keyboardLayout = .hanyuPinyin
        handler.syncWithPreferences()

        Preferences.keyboardLayout = .IBM
        handler.syncWithPreferences()

        Preferences.keyboardLayout = savedKeyboardLayout
        handler.syncWithPreferences()
    }

    func testIgnoreEmpty() {
        let input = KeyHandlerInput(
            inputText: "", keyCode: 0, charCode: 0, flags: [], isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreEnter() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.enter.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreUp() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.up.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result, "\(state)")
    }

    func testIgnoreDown() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.down.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result, "\(state)")
    }

    func testIgnoreLeft() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreRight() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.right.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnorePageUp() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.pageUp.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnorePageDown() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.pageDown.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreHome() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.home.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreEnd() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.end.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreDelete() {
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.delete.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreCommand() {
        let input = KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: 0, flags: .command, isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreOption() {
        let input = KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: 0, flags: .option, isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIgnoreNumericPad() {
        let input = KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: 0, flags: .numericPad, isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testIcuTransformAppendsPrintableInputAndBuildsCandidates() {
        let input = KeyHandlerInput(
            inputText: "a", keyCode: 0, charCode: charCode("a"), flags: [], isVerticalMode: false)
        var state: InputState = InputState.IcuTransform(string: "", candidates: [])
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
            XCTFail("ICU transform input should not fail")
        }

        XCTAssertTrue(result)
        XCTAssertTrue(state is InputState.IcuTransform, "\(state)")
        guard let state = state as? InputState.IcuTransform else {
            return
        }
        XCTAssertEqual(state.string, "a")
        XCTAssertTrue(state.candidates.contains("あ"))
        XCTAssertTrue(state.candidates.contains("ア"))
        XCTAssertFalse(state.candidates.contains("a"))
    }

    func testIcuTransformDeletesLastCharacterAndRefreshesCandidates() {
        let input = KeyHandlerInput(
            inputText: "", keyCode: 0, charCode: 8, flags: [], isVerticalMode: false)
        var state: InputState = InputState.IcuTransform(string: "ka", candidates: [])
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
            XCTFail("ICU transform delete should not fail")
        }

        XCTAssertTrue(result)
        XCTAssertTrue(state is InputState.IcuTransform, "\(state)")
        guard let state = state as? InputState.IcuTransform else {
            return
        }
        XCTAssertEqual(state.string, "k")
        XCTAssertTrue(state.candidates.contains("κ"))
        XCTAssertFalse(state.candidates.contains("か"))
    }

    func testIcuTransformDeleteEmptyStringReportsError() {
        let input = KeyHandlerInput(
            inputText: "", keyCode: 0, charCode: 8, flags: [], isVerticalMode: false)
        var state: InputState = InputState.IcuTransform(string: "", candidates: [])
        var didReportError = false
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
            didReportError = true
        }

        XCTAssertTrue(result)
        XCTAssertTrue(didReportError)
        XCTAssertEqual((state as? InputState.IcuTransform)?.string, "")
    }

    func testIcuTransformEscapeCancelsInput() {
        let input = KeyHandlerInput(
            inputText: "", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        var state: InputState = InputState.IcuTransform(string: "ka", candidates: [])
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
            XCTFail("ICU transform escape should not fail")
        }

        XCTAssertTrue(result)
        XCTAssertTrue(state is InputState.Empty, "\(state)")
    }

    func testIcuTransformIgnoresNonPrintableInput() {
        let input = KeyHandlerInput(
            inputText: "", keyCode: 0, charCode: 0, flags: [], isVerticalMode: false)
        var state: InputState = InputState.IcuTransform(string: "ka", candidates: [])
        var didChangeState = false
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
            didChangeState = true
        } errorCallback: {
            XCTFail("ICU transform non-printable input should not fail")
        }

        XCTAssertTrue(result)
        XCTAssertFalse(didChangeState)
        XCTAssertEqual((state as? InputState.IcuTransform)?.string, "ka")
    }

    func testIgnoreCapslock() {
        let input = KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: 0, flags: .capsLock, isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertFalse(result)
    }

    func testCapslock() {
        var input = KeyHandlerInput(
            inputText: "b", keyCode: 0, charCode: charCode("b"), flags: [], isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        var count = 0

        input = KeyHandlerInput(
            inputText: "a", keyCode: 0, charCode: charCode("a"), flags: .capsLock,
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            if count == 1 {
                state = newState
            }
            count += 1
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Committing, "\(state)")
        if let state = state as? InputState.Committing {
            XCTAssertEqual(state.poppedText, "a")
        }
    }

    func testCapslockShift() {
        var input = KeyHandlerInput(
            inputText: "b", keyCode: 0, charCode: charCode("b"), flags: [], isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        input = KeyHandlerInput(
            inputText: "a", keyCode: 0, charCode: charCode("a"), flags: [.capsLock, .shift],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Empty, "\(state)")
    }

    func testisNumericPad() {
        let current = Preferences.selectCandidateWithNumericKeypad
        Preferences.selectCandidateWithNumericKeypad = false
        defer {
            Preferences.selectCandidateWithNumericKeypad = current
        }

        var input = KeyHandlerInput(
            inputText: "b", keyCode: 0, charCode: charCode("b"), flags: [], isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        input = KeyHandlerInput(
            inputText: "1", keyCode: 0, charCode: charCode("1"), flags: .numericPad,
            isVerticalMode: false)
        var count = 0
        var empty: InputState = InputState.Empty()
        var target: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            switch count {
            case 0:
                state = newState
            case 1:
                target = newState
            case 2:
                empty = newState
            default:
                break
            }
            count += 1

        } errorCallback: {
        }

        XCTAssertEqual(count, 3)
        XCTAssertTrue(state is InputState.Empty, "\(state)")
        XCTAssertTrue(empty is InputState.Empty, "\(empty)")
        XCTAssertTrue(target is InputState.Committing, "\(target)")
        if let state = target as? InputState.Committing {
            XCTAssertEqual(state.poppedText, "1")
        }
    }

    // Regression test for #292.
    func testUppercaseLetterWhenEmpty1() {
        let current = Preferences.letterBehavior
        Preferences.letterBehavior = 0
        defer {
            Preferences.letterBehavior = current
        }
        let input = KeyHandlerInput(
            inputText: "A", keyCode: KeyCode.enter.rawValue, charCode: charCode("A"), flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        let result = handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertFalse(result)
    }

    func testUppercaseLetterWhenEmpty2() {
        let current = Preferences.letterBehavior
        Preferences.letterBehavior = 1
        defer {
            Preferences.letterBehavior = current
        }

        let input = KeyHandlerInput(
            inputText: "A", keyCode: KeyCode.enter.rawValue, charCode: charCode("A"), flags: [],
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "a")
        }
    }

    // Regression test for #292.
    func testUppercaseLetterWhenNotEmpty1() {
        let current = Preferences.letterBehavior
        Preferences.letterBehavior = 0
        defer {
            Preferences.letterBehavior = current
        }

        var state: InputState = InputState.Empty()
        let keys = Array("u6").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }

        let letterInput = KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: charCode("A"), flags: .shift,
            isVerticalMode: false)
        let result = handler.handle(input: letterInput, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertFalse(result)
    }

    // Regression test for #292.
    func testUppercaseLetterWhenNotEmpty2() {
        let current = Preferences.letterBehavior
        Preferences.letterBehavior = 1
        defer {
            Preferences.letterBehavior = current
        }

        var state: InputState = InputState.Empty()
        let keys = Array("u6").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }

        let letterInput = KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: charCode("A"), flags: .shift,
            isVerticalMode: false)
        handler.handle(input: letterInput, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "一a")
        }
    }

    func testSwitchInputSourceUponShiftLetterKeyComboRequestsConfiguredSourceAndLeavesEventUnhandled() {
        let savedSwitchInputSourceUponShiftLetterKeyComboInputSourceID = Preferences.switchInputSourceUponShiftLetterKeyComboInputSourceID
        defer {
            Preferences.switchInputSourceUponShiftLetterKeyComboInputSourceID = savedSwitchInputSourceUponShiftLetterKeyComboInputSourceID
        }
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = true
        Preferences.switchInputSourceUponShiftLetterKeyComboInputSourceID = "com.apple.keylayout.Vietnamese"
        var states: [InputState] = []
        let result = handler.handle(input: KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: charCode("A"), flags: .shift,
            isVerticalMode: false), state: InputState.Empty()) {
                states.append($0)
            } errorCallback: { XCTFail("Unexpected input error") }

        XCTAssertFalse(result)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual((states.first as? InputState.SwitchingInputSource)?.sourceID,
                       "com.apple.keylayout.Vietnamese")
    }

    func testSwitchInputSourceUponShiftLetterKeyComboClearsEngineAndPreservesCompositionState() {
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = true
        var state: InputState = InputState.Empty()
        for key in ["u", "6"] {
            _ = handler.handle(input: KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false), state: state) { state = $0 }
                errorCallback: { XCTFail("Unexpected composition error") }
        }
        XCTAssertTrue(state is InputState.Inputting)
        XCTAssertEqual((state as? InputState.Inputting)?.composingBuffer, "一")

        var states: [InputState] = []
        let result = handler.handle(input: KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: charCode("A"), flags: .shift,
            isVerticalMode: false), state: state) { states.append($0) }
            errorCallback: { XCTFail("Unexpected input error") }

        XCTAssertFalse(result)
        XCTAssertEqual(states.count, 1)
        XCTAssertTrue(states.first is InputState.SwitchingInputSource)
        XCTAssertEqual((state as? InputState.Inputting)?.composingBuffer, "一")
        XCTAssertEqual((handler.buildInputtingState() as? InputState.Inputting)?.composingBuffer, "")
    }

    // Deleting the final reading leaves EmptyIgnoringPreviousState, not Empty.
    func testSwitchInputSourceUponShiftLetterKeyComboAfterDeletingComposition() {
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = true
        var state: InputState = InputState.Empty()
        _ = handler.handle(input: KeyHandlerInput(
            inputText: "u", keyCode: 32, charCode: charCode("u"), flags: [],
            isVerticalMode: false), state: state) { state = $0 }
            errorCallback: { XCTFail("Unexpected composition error") }
        XCTAssertTrue(state is InputState.Inputting)

        _ = handler.handle(input: KeyHandlerInput(
            inputText: "\u{8}", keyCode: 51, charCode: 8, flags: [],
            isVerticalMode: false), state: state) { state = $0 }
            errorCallback: { XCTFail("Unexpected deletion error") }
        XCTAssertTrue(state is InputState.EmptyIgnoringPreviousState)

        var states: [InputState] = []
        let result = handler.handle(input: KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: charCode("A"), flags: .shift,
            isVerticalMode: false), state: state) { states.append($0) }
            errorCallback: { XCTFail("Unexpected input error") }
        XCTAssertFalse(result)
        XCTAssertEqual(states.count, 1)
        XCTAssertTrue(states.first is InputState.SwitchingInputSource)
    }

    func testSwitchInputSourceUponShiftLetterKeyComboOverridesUppercaseLetterBehavior() {
        let savedLetterBehavior = Preferences.letterBehavior
        defer { Preferences.letterBehavior = savedLetterBehavior }
        Preferences.letterBehavior = 0
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = true
        var states: [InputState] = []
        let result = handler.handle(input: KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: charCode("A"), flags: .shift,
            isVerticalMode: false), state: InputState.Empty()) { states.append($0) }
            errorCallback: { XCTFail("Unexpected input error") }

        XCTAssertFalse(result)
        XCTAssertEqual(states.count, 1)
        XCTAssertTrue(states.first is InputState.SwitchingInputSource)
    }

    func testSwitchInputSourceUponShiftLetterKeyComboOverridesLowercaseLetterBehavior() {
        let savedLetterBehavior = Preferences.letterBehavior
        defer { Preferences.letterBehavior = savedLetterBehavior }
        Preferences.letterBehavior = 1
        Preferences.switchInputSourceUponShiftLetterKeyComboEnabled = true
        var states: [InputState] = []
        let result = handler.handle(input: KeyHandlerInput(
            inputText: "A", keyCode: 0, charCode: charCode("A"), flags: .shift,
            isVerticalMode: false), state: InputState.Empty()) { states.append($0) }
        errorCallback: { XCTFail("Unexpected input error") }

        XCTAssertFalse(result)
        XCTAssertEqual(states.count, 1)
        XCTAssertTrue(states.first is InputState.SwitchingInputSource)
    }

    func testPunctuationTable() {
        let enabled = Preferences.halfWidthPunctuationEnabled
        Preferences.halfWidthPunctuationEnabled = false
        defer {
            Preferences.halfWidthPunctuationEnabled = enabled
        }

        let input = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.ChoosingCandidate, "\(state)")
        if let state = state as? InputState.ChoosingCandidate {
            XCTAssertTrue(state.candidates.map { $0.value }.contains("，"))
        }
    }

    func testIgnorePunctuationTable() {
        let enabled = Preferences.halfWidthPunctuationEnabled
        Preferences.halfWidthPunctuationEnabled = false

        defer {
            Preferences.halfWidthPunctuationEnabled = enabled
        }

        var state: InputState = InputState.Empty()
        var input = KeyHandlerInput(
            inputText: "1", keyCode: 0, charCode: charCode("1"), flags: .shift,
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        input = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "ㄅ")
        }
    }

    func testHalfPunctuationComma() {
        let enabled = Preferences.halfWidthPunctuationEnabled
        Preferences.halfWidthPunctuationEnabled = true
        defer {
            Preferences.halfWidthPunctuationEnabled = enabled
        }

        let input = KeyHandlerInput(
            inputText: "<", keyCode: 0, charCode: charCode("<"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, ",")
        }
    }

    func testPunctuationComma() {
        let enabled = Preferences.halfWidthPunctuationEnabled
        Preferences.halfWidthPunctuationEnabled = false
        defer {
            Preferences.halfWidthPunctuationEnabled = enabled
        }
        let input = KeyHandlerInput(
            inputText: "<", keyCode: 0, charCode: charCode("<"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "，")
        }
    }

    func testHalfPunctuationPeriod() {
        let enabled = Preferences.halfWidthPunctuationEnabled
        Preferences.halfWidthPunctuationEnabled = true
        defer {
            Preferences.halfWidthPunctuationEnabled = enabled
        }
        let input = KeyHandlerInput(
            inputText: ">", keyCode: 0, charCode: charCode(">"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, ".")
        }
    }

    func testPunctuationPeriod() {
        let enabled = Preferences.halfWidthPunctuationEnabled
        Preferences.halfWidthPunctuationEnabled = false
        defer {
            Preferences.halfWidthPunctuationEnabled = enabled
        }

        let input = KeyHandlerInput(
            inputText: ">", keyCode: 0, charCode: charCode(">"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "。")
        }
    }

    func testCtrlPunctuationPeriod() {
        let enabled = Preferences.halfWidthPunctuationEnabled
        Preferences.halfWidthPunctuationEnabled = false
        defer {
            Preferences.halfWidthPunctuationEnabled = enabled
        }

        let input = KeyHandlerInput(
            inputText: ".", keyCode: 0, charCode: charCode("."), flags: .control,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "。")
        }
    }

    func testInvalidBpmf() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        let keepReadingUponCompositionError = Preferences.keepReadingUponCompositionError
        Preferences.associatedPhrasesEnabled = false
        Preferences.keepReadingUponCompositionError = false
        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
            Preferences.keepReadingUponCompositionError = keepReadingUponCompositionError
        }

        var state: InputState = InputState.Empty()
        let keys = Array("ni4").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.EmptyIgnoringPreviousState, "\(state)")
    }

    func testInputting() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false

        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("vul3a945j4up gj bj4z83").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "小麥注音輸入法")
        }
    }

    func testInputtingNihao() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
        }
    }

    func testInputtingTianKong() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("wu0 dj/ ").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "天空")
        }
    }

    func testCommittingNihao() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
        }

        let enter = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [], isVerticalMode: false)
        var committing: InputState?
        var empty: InputState?
        var count = 0

        handler.handle(input: enter, state: state) { newState in
            switch count {
            case 0:
                committing = newState
            case 1:
                empty = newState
            default:
                break
            }
            count += 1
        } errorCallback: {
        }

        XCTAssertTrue(committing is InputState.Committing, "\(state)")
        if let committing = committing as? InputState.Committing {
            XCTAssertEqual(committing.poppedText, "你好")
        }
        XCTAssertTrue(empty is InputState.Empty, "\(state)")
    }

    func testDelete() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        let left = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        let delete = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.delete.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var errorCalled = false

        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 1)
        }

        handler.handle(input: delete, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
        }

        handler.handle(input: delete, state: state) { newState in
            state = newState
        } errorCallback: {
            errorCalled = true
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
        }
        XCTAssertTrue(errorCalled)

        errorCalled = false

        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 0)
        }

        handler.handle(input: delete, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.EmptyIgnoringPreviousState, "\(state)")
    }

    func testBackspaceToDeleteReading() {
        var state: InputState = InputState.Empty()
        let keys = Array("su").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }

        let backspace = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 8, flags: [], isVerticalMode: false)

        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "ㄋ")
            XCTAssertEqual(state.cursorIndex, 1)
        }

        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.EmptyIgnoringPreviousState, "\(state)")
    }

    func testBackspaceAtBegin() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }

        let left = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 0)
        }

        let backspace = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 8, flags: [], isVerticalMode: false)
        var errorCall = false
        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
            errorCall = true
        }
        XCTAssertTrue(errorCall)
    }

    func testBackspaceToDeleteReadingWithText() {
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }

        let backspace = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 8, flags: [], isVerticalMode: false)

        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你ㄏ")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
        }
    }

    func testBackspace() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        let backspace = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 8, flags: [], isVerticalMode: false)

        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
        }

        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.EmptyIgnoringPreviousState, "\(state)")

    }

    func testCursorWithReading() {
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let left = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        let right = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.right.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var leftErrorCalled = false
        var rightErrorCalled = false

        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
            leftErrorCalled = true
        }

        handler.handle(input: right, state: state) { newState in
            state = newState
        } errorCallback: {
            rightErrorCalled = true
        }

        XCTAssertTrue(leftErrorCalled)
        XCTAssertTrue(rightErrorCalled)
    }

    func testCursor() {

        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        let left = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        let right = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.right.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)

        var errorCalled = false

        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 1)
        }

        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 0)
        }

        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
            errorCalled = true
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 0)
        }
        XCTAssertTrue(errorCalled)

        handler.handle(input: right, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 1)
        }

        handler.handle(input: right, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        errorCalled = false
        handler.handle(input: right, state: state) { newState in
            state = newState
        } errorCallback: {
            errorCalled = true
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }
        XCTAssertTrue(errorCalled)
        Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
    }

    func testCandidateWithDown() {
        var state: InputState = InputState.Empty()
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        let selectPhraseAfterCursorAsCandidate = Preferences.selectPhraseAfterCursorAsCandidate
        let moveCursorAfterSelectingCandidate = Preferences.moveCursorAfterSelectingCandidate
        Preferences.associatedPhrasesEnabled = false
        Preferences.selectPhraseAfterCursorAsCandidate = false
        Preferences.moveCursorAfterSelectingCandidate = false

        defer {
            Preferences.selectPhraseAfterCursorAsCandidate = selectPhraseAfterCursorAsCandidate
            Preferences.moveCursorAfterSelectingCandidate = moveCursorAfterSelectingCandidate
        }

        let keys = Array("su3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
        }

        let down = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.down.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        handler.handle(input: down, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.ChoosingCandidate, "\(state)")
        if let state = state as? InputState.ChoosingCandidate {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
            let candidates = state.candidates
            XCTAssertTrue(candidates.map { $0.value }.contains("你"))
        }

        Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
    }

    func testCandidateWithSpace() {
        let enabled = Preferences.chooseCandidateUsingSpace
        let selectPhraseAfterCursorAsCandidate = Preferences.selectPhraseAfterCursorAsCandidate
        let moveCursorAfterSelectingCandidate = Preferences.moveCursorAfterSelectingCandidate
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.chooseCandidateUsingSpace = true
        Preferences.selectPhraseAfterCursorAsCandidate = false
        Preferences.moveCursorAfterSelectingCandidate = false
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.chooseCandidateUsingSpace = enabled
            Preferences.selectPhraseAfterCursorAsCandidate = selectPhraseAfterCursorAsCandidate
            Preferences.moveCursorAfterSelectingCandidate = moveCursorAfterSelectingCandidate
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
        }

        let space = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 32, flags: [], isVerticalMode: false)
        handler.handle(input: space, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.ChoosingCandidate, "\(state)")
        if let state = state as? InputState.ChoosingCandidate {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
            let candidates = state.candidates
            XCTAssertTrue(candidates.map { $0.value }.contains("你"))
        }

    }

    func testInputSpace() {
        let enabled = Preferences.chooseCandidateUsingSpace
        let associatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.chooseCandidateUsingSpace = false
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.chooseCandidateUsingSpace = enabled
            Preferences.associatedPhrasesEnabled = associatedPhrases
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
        }

        var count = 0
        var target: InputState = InputState.Empty()
        var empty: InputState = InputState.Empty()

        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 32, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            switch count {
            case 0:
                state = newState
            case 1:
                target = newState
            case 2:
                empty = newState
            default:
                break
            }
            count += 1
        } errorCallback: {
        }

        XCTAssertEqual(count, 3)
        XCTAssertTrue(state is InputState.Committing, "\(state)")
        if let state = state as? InputState.Committing {
            XCTAssertEqual(state.poppedText, "你")
        }
        XCTAssertTrue(target is InputState.Committing, "\(target)")
        if let target = target as? InputState.Committing {
            XCTAssertEqual(target.poppedText, " ")
        }
        XCTAssertTrue(empty is InputState.Empty, "\(empty)")
    }

    func testInputSpaceInBetween() {
        let enabled = Preferences.chooseCandidateUsingSpace
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.chooseCandidateUsingSpace = false
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.chooseCandidateUsingSpace = enabled
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
        }

        var input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 32, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你 好")
        }
    }

    func testHomeAndEnd() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        let home = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.home.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        let end = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.end.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)

        handler.handle(input: home, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 0)
        }

        var homeErrorCalled = false
        handler.handle(input: home, state: state) { newState in
            state = newState
        } errorCallback: {
            homeErrorCalled = true
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 0)
        }
        XCTAssertTrue(homeErrorCalled)

        handler.handle(input: end, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        var endErrorCalled = false
        handler.handle(input: end, state: state) { newState in
            state = newState
        } errorCallback: {
            endErrorCalled = true
        }

        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }
        XCTAssertTrue(endErrorCalled)
    }

    func testHomeAndEndWithReading() {
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你ㄏㄠ")
            XCTAssertEqual(state.cursorIndex, 3)
        }

        let home = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.home.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        let end = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.end.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        var homeErrorCalled = false
        var endErrorCalled = false

        handler.handle(input: home, state: state) { newState in
            state = newState
        } errorCallback: {
            homeErrorCalled = true
        }

        XCTAssertTrue(homeErrorCalled)
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你ㄏㄠ")
            XCTAssertEqual(state.cursorIndex, 3)
        }

        handler.handle(input: end, state: state) { newState in
            state = newState
        } errorCallback: {
            endErrorCalled = true
        }

        XCTAssertTrue(endErrorCalled)
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你ㄏㄠ")
            XCTAssertEqual(state.cursorIndex, 3)
        }
    }

    func testMarkingLeftAtBegin() {
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }

        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: .shift,
            isVerticalMode: false)
        var errorCalled = false

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
            errorCalled = true
        }
        XCTAssertTrue(errorCalled)
    }

    func testMarkingRightAtEnd() {
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }

        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.right.rawValue, charCode: 0, flags: .shift,
            isVerticalMode: false)
        var errorCalled = false
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
            errorCalled = true
        }
        XCTAssertTrue(errorCalled)
    }

    func testMarkingLeft() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        var input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: .shift,
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Marking, "\(state)")
        if let state = state as? InputState.Marking {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
            XCTAssertEqual(state.markerIndex, 1)
            XCTAssertEqual(state.markedRange, NSRange(location: 1, length: 1))
        }

        input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: .shift,
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Marking, "\(state)")
        if let state = state as? InputState.Marking {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
            XCTAssertEqual(state.markerIndex, 0)
            XCTAssertEqual(state.markedRange, NSRange(location: 0, length: 2))
        }

        var stateForGoingRight: InputState = state

        let right = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.right.rawValue, charCode: 0, flags: .shift,
            isVerticalMode: false)
        handler.handle(input: right, state: stateForGoingRight) { newState in
            stateForGoingRight = newState
        } errorCallback: {
        }
        handler.handle(input: right, state: stateForGoingRight) { newState in
            stateForGoingRight = newState
        } errorCallback: {
        }

        XCTAssertTrue(stateForGoingRight is InputState.Inputting, "\(stateForGoingRight)")
    }

    func testMarkingRight() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        let left = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        handler.handle(input: left, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        let errorInput = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: .shift,
            isVerticalMode: false)
        var errorCalled = false
        handler.handle(input: errorInput, state: state) { newState in
            state = newState
        } errorCallback: {
            errorCalled = true
        }
        XCTAssertTrue(errorCalled)

        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.right.rawValue, charCode: 0, flags: .shift,
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Marking, "\(state)")
        if let state = state as? InputState.Marking {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 0)
            XCTAssertEqual(state.markerIndex, 1)
            XCTAssertEqual(state.markedRange, NSRange(location: 0, length: 1))
        }

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Marking, "\(state)")
        if let state = state as? InputState.Marking {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 0)
            XCTAssertEqual(state.markerIndex, 2)
            XCTAssertEqual(state.markedRange, NSRange(location: 0, length: 2))
        }

        var stateForGoingLeft: InputState = state

        handler.handle(input: left, state: stateForGoingLeft) { newState in
            stateForGoingLeft = newState
        } errorCallback: {
        }
        handler.handle(input: left, state: stateForGoingLeft) { newState in
            stateForGoingLeft = newState
        } errorCallback: {
        }

        XCTAssertTrue(stateForGoingLeft is InputState.Inputting, "\(stateForGoingLeft)")
    }

    func testCancelMarking() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        var input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.left.rawValue, charCode: 0, flags: .shift,
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Marking, "\(state)")
        if let state = state as? InputState.Marking {
            XCTAssertEqual(state.composingBuffer, "你好")
            XCTAssertEqual(state.cursorIndex, 2)
            XCTAssertEqual(state.markerIndex, 1)
            XCTAssertEqual(state.markedRange, NSRange(location: 1, length: 1))
        }

        input = KeyHandlerInput(
            inputText: "1", keyCode: 0, charCode: charCode("1"), flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你好ㄅ")
        }
    }

    func testEscToClearReadingAndGoToEmpty() {
        let enabled = Preferences.escToCleanInputBuffer
        Preferences.escToCleanInputBuffer = false
        defer {
            Preferences.escToCleanInputBuffer = enabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "ㄋㄧ")
            XCTAssertEqual(state.cursorIndex, 2)
        }

        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.EmptyIgnoringPreviousState, "\(state)")
    }

    func testEscToClearReadingAndGoToInputting() {
        let enabled = Preferences.escToCleanInputBuffer
        Preferences.escToCleanInputBuffer = false
        defer {
            Preferences.escToCleanInputBuffer = enabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你ㄏㄠ")
            XCTAssertEqual(state.cursorIndex, 3)
        }

        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你")
            XCTAssertEqual(state.cursorIndex, 1)
        }
    }

    func testEscToClearAll() {
        let enabled = Preferences.escToCleanInputBuffer
        Preferences.escToCleanInputBuffer = true
        defer {
            Preferences.escToCleanInputBuffer = enabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, "你ㄏㄠ")
            XCTAssertEqual(state.cursorIndex, 3)
        }

        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.EmptyIgnoringPreviousState, "\(state)")
    }

    func testEscKey() {
        var state: InputState = InputState.Empty()
        let keys = Array("w8").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [],
            isVerticalMode: false)

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.EmptyIgnoringPreviousState)
    }

    func testEscKeyWithCandidate() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("w8 ").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let down = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.down.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)

        handler.handle(input: down, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.ChoosingCandidate)

        let esc = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [],
            isVerticalMode: false)

        handler.handle(input: esc, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting)
    }

    func testHomeKey() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("w8 ").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.home.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting)
        if let state = state as? InputState.Inputting {
            XCTAssertTrue(state.cursorIndex == 0)
        }
    }

    func testHomeAndEndKey() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("w8 ").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let home = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.home.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)

        handler.handle(input: home, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        let end = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.end.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)

        handler.handle(input: end, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting)
        if let state = state as? InputState.Inputting {
            XCTAssertTrue(state.cursorIndex == 1)
        }
    }

    func testTabKey() {
        var state: InputState = InputState.Empty()
        let keys = Array("w8 ").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.tab.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting)
    }

    func testMacroAndTabKey() {
        var state: InputState = InputState.Empty()
        // 今天
        let keys = Array("rup wu0 ").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.tab.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssertTrue(state is InputState.Inputting)
    }

    func testLookUpCandidateInDictionaryAndCancelWithTabKey() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("wu0 dj/ ").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        var input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.down.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        input = KeyHandlerInput(
            inputText: "?", keyCode: 0, charCode: 0, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssert(state is InputState.SelectingDictionary)

        input = KeyHandlerInput(
            inputText: "?", keyCode: 0, charCode: 0, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssert(state is InputState.ChoosingCandidate)
    }

    func testLookUpCandidateInDictionaryAndCancelWithEscKey() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        var state: InputState = InputState.Empty()
        let keys = Array("wu0 dj/ ").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        var input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.down.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        input = KeyHandlerInput(
            inputText: "?", keyCode: 0, charCode: 0, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssert(state is InputState.SelectingDictionary)

        input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssert(state is InputState.ChoosingCandidate)
    }

}

extension KeyHandlerBopomofoTests {
    func testSelectingFeature() {
        var state: InputState = InputState.Empty()
        let input = KeyHandlerInput(
            inputText: "\\", keyCode: 42, charCode: charCode("\\"), flags: [.control],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssert(state is InputState.SelectingFeature)
    }
}

extension KeyHandlerBopomofoTests {
    func testEnterBig5() {
        let big5InputEnabled = Preferences.big5InputEnabled
        Preferences.big5InputEnabled = true
        var state: InputState = InputState.Big5(code: "")

        let input = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: [.control],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssert(state is InputState.Big5)
        Preferences.big5InputEnabled = big5InputEnabled
    }

    func testBig5Input() {
        var state: InputState = InputState.Big5(code: "")
        var commitState: InputState?
        XCTAssert(state is InputState.Big5)
        let keys = Array("a143").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
                if newState is InputState.Committing {
                    commitState = newState
                }
            } errorCallback: {
            }
        }
        XCTAssert(state is InputState.Empty)
        XCTAssert(commitState is InputState.Committing)
        if let commitState = commitState as? InputState.Committing {
            XCTAssertTrue(commitState.poppedText == "。")
        }
    }

    func testBig5Cancel() {
        var state: InputState = InputState.Big5(code: "")
        XCTAssert(state is InputState.Big5)
        let keys = Array("a14").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssert(state is InputState.Empty)
    }

    func testBig5Delete() {
        var state: InputState = InputState.Big5(code: "")
        XCTAssert(state is InputState.Big5)
        let keys = Array("a14").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.delete.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssert(state is InputState.Big5)
        if let state = state as? InputState.Big5 {
            XCTAssertTrue(state.code == "A1")
        }
    }

}

extension KeyHandlerBopomofoTests {
    func testCtrlEnter1() {
        let controlEnterOutput = Preferences.controlEnterOutput
        Preferences.controlEnterOutput = .bpmfReading
        var state: InputState = InputState.Empty()
        var commitState: InputState?
        let keys = Array("su3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
                if newState is InputState.Committing {
                    commitState = newState
                }
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [.control],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
            if newState is InputState.Committing {
                commitState = newState
            }
        } errorCallback: {
        }

        XCTAssert(state is InputState.Empty)
        XCTAssert(commitState is InputState.Committing)
        if let commitState = commitState as? InputState.Committing {
            XCTAssertTrue(commitState.poppedText == "ㄋㄧˇ")
        }
        Preferences.controlEnterOutput = controlEnterOutput
    }

    func testCtrlEnter2() {
        let controlEnterOutput = Preferences.controlEnterOutput
        Preferences.controlEnterOutput = .htmlRuby
        var state: InputState = InputState.Empty()
        var commitState: InputState?
        let keys = Array("su3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
                if newState is InputState.Committing {
                    commitState = newState
                }
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [.control],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
            if newState is InputState.Committing {
                commitState = newState
            }
        } errorCallback: {
        }

        XCTAssert(state is InputState.Empty)
        XCTAssert(commitState is InputState.Committing)
        if let commitState = commitState as? InputState.Committing {
            XCTAssertTrue(
                commitState.poppedText == "<ruby>你<rp>(</rp><rt>ㄋㄧˇ</rt><rp>)</rp></ruby>")
        }
        Preferences.controlEnterOutput = controlEnterOutput
    }

    func testCtrlEnter3() {
        let controlEnterOutput = Preferences.controlEnterOutput
        Preferences.controlEnterOutput = .brailleUnicode
        var state: InputState = InputState.Empty()
        var commitState: InputState?
        let keys = Array("su3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
                if newState is InputState.Committing {
                    commitState = newState
                }
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [.control],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
            if newState is InputState.Committing {
                commitState = newState
            }
        } errorCallback: {
        }

        XCTAssert(state is InputState.Empty)
        XCTAssert(commitState is InputState.Committing)
        if let commitState = commitState as? InputState.Committing {
            XCTAssertTrue(commitState.poppedText == "⠝⠡⠈")
        }
        Preferences.controlEnterOutput = controlEnterOutput
    }
}

extension KeyHandlerBopomofoTests {
    func testEnterAssocatedPhrases() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = true
        var state: InputState = InputState.Empty()
        let keys = Array("5j/ cj86").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [.shift],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssert(state is InputState.AssociatedPhrases)
        if let state = state as? InputState.AssociatedPhrases {
            XCTAssert(state.composingBuffer == "中華")
            XCTAssert(state.prefixReading == "ㄓㄨㄥ-ㄏㄨㄚˊ")
            XCTAssert(state.candidate(at: 0) == "民國")
        }

        Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
    }

    func testEnterAssocatedPunctuaton() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = true
        var state: InputState = InputState.Empty()
        let keys = Array("{").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [.shift],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssert(state is InputState.AssociatedPhrases)
        if let state = state as? InputState.AssociatedPhrases {
            XCTAssert(state.composingBuffer == "『")
            XCTAssert(state.prefixReading == "_punctuation_{")
            XCTAssert(state.candidate(at: 0) == "』")
        }

        Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
    }

    func testCancelAssocatedPhrases() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = true
        var state: InputState = InputState.Empty()
        let keys = Array("5j/ cj86").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let shiftEnter = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [.shift],
            isVerticalMode: false)
        handler.handle(input: shiftEnter, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        let input = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }

        XCTAssert(state is InputState.Inputting)
        if let state = state as? InputState.Inputting {
            XCTAssert(state.composingBuffer == "中華")
        }
        Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
    }

    func testSelectAssocatedPhrases() {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        var state: InputState = InputState.Empty()
        let keys = Array("5j/ cj86").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        let shitEnter = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [.shift],
            isVerticalMode: false)
        handler.handle(input: shitEnter, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssert(state is InputState.AssociatedPhrases)
        let input = KeyHandlerInput(
            inputText: "1", keyCode: 0, charCode: charCode("1"), flags: [.shift],
            isVerticalMode: false)
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssert(state is InputState.AssociatedPhrases)
        guard let associatedPhrasesState = state as? InputState.AssociatedPhrases else {
            XCTFail()
            return
        }
        handler.fixNodeForAssociatedPhraseWithPrefix(
            at: Int(associatedPhrasesState.cursorIndex),
            prefixReading: associatedPhrasesState.prefixReading,
            prefixValue: associatedPhrasesState.prefixValue,
            associatedPhraseReading: associatedPhrasesState.candidates[0].reading,
            associatedPhraseValue: associatedPhrasesState.candidates[0].value)
        let finalState = handler.buildInputtingState()
        XCTAssert(finalState is InputState.Inputting)
        if let finalState = finalState as? InputState.Inputting {
            XCTAssertTrue(finalState.composingBuffer == "中華民國")
        }
        Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
    }
}

extension KeyHandlerBopomofoTests {
    func testForceCommit() {
        var state: InputState = InputState.Empty()
        let keys = Array("5j/ cj86").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        handler.handleForceCommit { newState in
            state = newState
        }
        XCTAssertTrue(state is InputState.Committing)
        if let state = state as? InputState.Committing {
            XCTAssertTrue(state.poppedText == "中華")
        }
    }
}

extension KeyHandlerBopomofoTests {
    func testNumberTypingAndCommitWithEnter() {
        var state: InputState = InputState.Number(number: "", candidates: [])
        for ch in Array("12345") {
            let s = String(ch)
            let input = KeyHandlerInput(
                inputText: s, keyCode: 0, charCode: charCode(s), flags: [], isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Number, "\(state)")
        if let numberState = state as? InputState.Number {
            XCTAssertEqual(numberState.number, "12345")
            XCTAssertTrue(numberState.composingBuffer.hasSuffix("12345"))
        }

        var committing: InputState?
        var empty: InputState?
        var count = 0
        let enter = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 13, flags: [], isVerticalMode: false)
        handler.handle(input: enter, state: state) { newState in
            switch count {
            case 0: committing = newState
            case 1: empty = newState
            default: break
            }
            count += 1
        } errorCallback: {
        }

        XCTAssertEqual(count, 2)
        XCTAssertTrue(committing is InputState.Committing, "\(String(describing: committing))")
        if let committing = committing as? InputState.Committing {
            XCTAssertEqual(committing.poppedText, "一萬二千三百四十五")
        }
        XCTAssertTrue(empty is InputState.Empty, "\(String(describing: empty))")
    }

    func testNumberBackspaceAndEsc() {
        var state: InputState = InputState.Number(number: "123", candidates: [])
        let backspace = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 8, flags: [], isVerticalMode: false)
        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Number, "\(state)")
        if let numberState = state as? InputState.Number {
            XCTAssertEqual(numberState.number, "12")
        }

        let esc = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: esc, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(
            state is InputState.EmptyIgnoringPreviousState || state is InputState.Empty, "\(state)")
    }

    func testNumberIgnoresNonDigit() {
        var state: InputState = InputState.Number(number: "9", candidates: [])
        let letter = KeyHandlerInput(
            inputText: "a", keyCode: 0, charCode: charCode("a"), flags: [], isVerticalMode: false)
        let _ = handler.handle(input: letter, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        // Expect still Number with unchanged buffer
        XCTAssertTrue(state is InputState.Number, "\(state)")
        if let numberState = state as? InputState.Number {
            XCTAssertEqual(numberState.number, "9")
        }
    }

    func testNumberChineseCandidates() {
        var state: InputState = InputState.Number(number: "", candidates: [])
        let keys = Array("123").map { String($0) }
        for ch in keys {
            let input = KeyHandlerInput(
                inputText: ch, keyCode: 0, charCode: charCode(ch), flags: [], isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Number, "\(state)")
        if let numberState = state as? InputState.Number {
            XCTAssertEqual(numberState.number, "123")
            XCTAssertTrue(numberState.candidates.contains("一百二十三"))
            XCTAssertTrue(numberState.candidates.contains("壹佰貳拾參"))
            XCTAssertTrue(numberState.candidates.contains("CXXIII"))  // Roman numeral for 123
        }
    }

    func testNumberDecimalPointAndChineseCandidates() {
        var state: InputState = InputState.Number(number: "", candidates: [])
        let keys = Array("12.34").map { String($0) }
        for ch in keys {
            let input = KeyHandlerInput(
                inputText: ch, keyCode: 0, charCode: charCode(ch), flags: [], isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Number, "\(state)")
        if let numberState = state as? InputState.Number {
            XCTAssertEqual(numberState.number, "12.34")
            XCTAssertTrue(numberState.candidates.contains("一十二點三四"))
            XCTAssertTrue(numberState.candidates.contains("壹拾貳點參肆"))
            XCTAssertFalse(numberState.candidates.contains("XII.XXXIV"))  // Roman numerals should not be present for decimals
        }
    }

    func testNumberRomanCandidatesOutOfRange() {
        var state: InputState = InputState.Number(number: "", candidates: [])
        let keys = Array("4000").map { String($0) }  // Max Roman is 3999
        for ch in keys {
            let input = KeyHandlerInput(
                inputText: ch, keyCode: 0, charCode: charCode(ch), flags: [], isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Number, "\(state)")
        if let numberState = state as? InputState.Number {
            XCTAssertEqual(numberState.number, "4000")
            XCTAssertTrue(numberState.candidates.contains("四千"))
            XCTAssertTrue(numberState.candidates.contains("肆仟"))
            XCTAssertFalse(numberState.candidates.contains("MMMM"))  // Should not contain Roman numeral
        }
    }
}

extension KeyHandlerBopomofoTests {

    func checkChangingReadingUsingToneKey(input: String, expected: String) {
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        let allowChangingPriorTone = Preferences.allowChangingPriorTone
        Preferences.associatedPhrasesEnabled = false
        Preferences.allowChangingPriorTone = true
        defer {
            Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled
            Preferences.allowChangingPriorTone = allowChangingPriorTone
        }

        var state: InputState = InputState.Empty()
        let keys = Array(input).map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, expected)
        }
    }

    // Input 小麥 then change to tone 3
    func testChangingReadingUsingToneKey1() {
        checkChangingReadingUsingToneKey(input: "vul3a943", expected: "小買")
    }

    // Input 小麥 then change to tone 4
    func testChangingReadingUsingToneKey2() {
        checkChangingReadingUsingToneKey(input: "vul3a946", expected: "小埋")
    }

    // Input 小麥 then change to tone 5
    func testChangingReadingUsingToneKey3() {
        checkChangingReadingUsingToneKey(input: "vul3a947", expected: "小麥˙")
    }

    func testBopomofoFontAnnotationSupport(input: String, expected: String) {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }

        let bopomofoFontAnnotationSupportEnabled = Preferences.bopomofoFontAnnotationSupportEnabled
        Preferences.bopomofoFontAnnotationSupportEnabled = true
        defer {
            Preferences.bopomofoFontAnnotationSupportEnabled = bopomofoFontAnnotationSupportEnabled
        }

        var state: InputState = InputState.Empty()
        let keys = Array(input).map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let state = state as? InputState.Inputting {
            XCTAssertEqual(state.composingBuffer, expected)
        }
    }

    func testBopomofoFontAnnotationSupport_BaseCase() {
        testBopomofoFontAnnotationSupport(input: "u u <u6ek7", expected: "一一，一\u{E01E1}個\u{E01E1}")
    }
}

extension KeyHandlerBopomofoTests {

    func testInputBufferThenBacktickThenEsc() {
        // Type something in the buffer, then press ` to enter choosing punctuation list, then ESC to return to inputting state
        var state: InputState = InputState.Empty()
        // Type a valid Bopomofo key (e.g., 's' for ㄋ)
        let input1 = KeyHandlerInput(
            inputText: "s", keyCode: 0, charCode: charCode("s"), flags: .shift,
            isVerticalMode: false)
        handler.handle(input: input1, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        // Press `
        let backtick = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        handler.handle(input: backtick, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        // Press ESC
        let esc = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: esc, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        // Should return to inputting state with buffer preserved
        XCTAssertTrue(
            state is InputState.EmptyIgnoringPreviousState,
            "\(state)"
        )
    }

    func testInputBufferWithCharactersThenBacktickThenEsc() {
        let asociatedPhrases = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer {
            Preferences.associatedPhrasesEnabled = asociatedPhrases
        }
        // Type something in the buffer, then press ` to enter choosing punctuation list, then ESC to return to inputting state
        var state: InputState = InputState.Empty()

        let keys = Array("su3cl3").map {
            String($0)
        }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }

        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        // Press `
        let backtick = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        handler.handle(input: backtick, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.ChoosingPunctuationList, "\(state)")
        // Press ESC
        let esc = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [], isVerticalMode: false)
        handler.handle(input: esc, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        // Should return to inputting state with buffer preserved
        XCTAssertTrue(
            state is InputState.Inputting,
            "\(state)"
        )
        if let inputting = state as? InputState.Inputting {
            XCTAssertEqual(inputting.composingBuffer, "你好")
        }
    }

    func testBacktickKey() {
        // Handle ` key
        let input = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.ChoosingCandidate, "\(state)")
    }

    func testBacktickThenEsc() {
        // zonble
        // Handle ` key then ESC
        let input = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(
            state is InputState.ChoosingPunctuationList,
            "\(state)"
        )
        let esc = KeyHandlerInput(
            inputText: " ", keyCode: 0, charCode: 27, flags: [],
            isVerticalMode: false)
        handler.handle(input: esc, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(
            state is InputState.EmptyIgnoringPreviousState,
            "\(state)"
        )
    }

    func testBacktickThenBackspace() {
        // Handle ` key then Backspace
        let input = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(
            state is InputState.ChoosingPunctuationList,
            "\(state)"
        )
        let backspace = KeyHandlerInput(
            inputText: " ", keyCode: KeyCode.delete.rawValue, charCode: 0, flags: [],
            isVerticalMode: false)
        handler.handle(input: backspace, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(
            state is InputState.EmptyIgnoringPreviousState,
            "\(state)"
        )
    }

    func testBacktickThenBacktick() {
        // Handle ` key then ` key
        let input = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        let input2 = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        handler.handle(input: input2, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        // Should remain in candidate state or reset, depending on implementation
        XCTAssertTrue(state is InputState.SelectingFeature, "\(state)")
    }

    func testBacktickThenPunctuation() {
        // Handle ` key then valid punctuation (e.g., < for comma)
        let input = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: .shift,
            isVerticalMode: false)
        var state: InputState = InputState.Empty()
        handler.handle(input: input, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        let punct = KeyHandlerInput(
            inputText: "<", keyCode: 0, charCode: charCode("<"), flags: .shift,
            isVerticalMode: false)
        handler.handle(input: punct, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        // Should either commit a punctuation or reset
        XCTAssertTrue(
            state is InputState.ChoosingCandidate || state is InputState.EmptyIgnoringPreviousState
                || state is InputState.Inputting, "\(state)")
    }

    func testDoubleBackquoteForceCommit() {
        // Prepare input: su3cl3 → "你好"
        let associatedPhrasesEnabled = Preferences.associatedPhrasesEnabled
        Preferences.associatedPhrasesEnabled = false
        defer { Preferences.associatedPhrasesEnabled = associatedPhrasesEnabled }

        var state: InputState = InputState.Empty()
        let keys = Array("su3cl3").map { String($0) }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        XCTAssertTrue(state is InputState.Inputting, "\(state)")
        if let inputting = state as? InputState.Inputting {
            XCTAssertEqual(inputting.composingBuffer, "你好")
        }

        // First backquote: should not commit yet
        let backquote = KeyHandlerInput(
            inputText: "`", keyCode: 0, charCode: charCode("`"), flags: [], isVerticalMode: false)
        handler.handle(input: backquote, state: state) { newState in
            state = newState
        } errorCallback: {
        }
        // Should still be inputting
        XCTAssertTrue(state is InputState.ChoosingPunctuationList, "\(state)")

        var commiting: InputState.Committing?
        // Second backquote: should force commit
        handler.handle(input: backquote, state: state) { newState in
            if let newState = newState as? InputState.Committing {
                commiting = newState
            }
            state = newState
        } errorCallback: {
        }
        XCTAssertTrue(state is InputState.SelectingFeature, "\(state)")
        XCTAssertNotNil(commiting)
        if let committing = commiting {
            XCTAssertEqual(committing.poppedText, "你好")
        }
    }

    func testJingJingTi() {
        var state: InputState = InputState.Empty()
        let keys = Array("ru/ ru/ wu3").map { String($0) }
        for key in keys {
            let input = KeyHandlerInput(
                inputText: key, keyCode: 0, charCode: charCode(key), flags: [],
                isVerticalMode: false)
            handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {
            }
        }
        if let inputting = state as? InputState.Inputting {
            XCTAssertEqual(inputting.composingBuffer, "晶晶體")
        } else {
            XCTFail("State is not Inputting: \(state)")
        }
    }

    func testNewKeyboardLogicPunctuation() {
        // 1. Direct backslash (\) should output Chinese dunhao (、)
        do {
            handler.clear()
            var state: InputState = InputState.Empty()
            let input = KeyHandlerInput(
                inputText: "\\", keyCode: 42, charCode: charCode("\\"), flags: [],
                isVerticalMode: false)
            let handled = handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {}
            XCTAssertTrue(handled)
            if let inputting = state as? InputState.Inputting {
                XCTAssertEqual(inputting.composingBuffer, "、")
            } else {
                XCTFail("State is not Inputting for \\: \(state)")
            }
        }

        // 2. Direct single quote (') should output Chinese dunhao (、)
        do {
            handler.clear()
            var state: InputState = InputState.Empty()
            let input = KeyHandlerInput(
                inputText: "'", keyCode: 39, charCode: charCode("'"), flags: [],
                isVerticalMode: false)
            let handled = handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {}
            XCTAssertTrue(handled)
            if let inputting = state as? InputState.Inputting {
                XCTAssertEqual(inputting.composingBuffer, "、")
            } else {
                XCTFail("State is not Inputting for ': \(state)")
            }
        }

        // 3. Direct equal (=) should output half-width '='
        do {
            handler.clear()
            var state: InputState = InputState.Empty()
            let input = KeyHandlerInput(
                inputText: "=", keyCode: 24, charCode: charCode("="), flags: [],
                isVerticalMode: false)
            let handled = handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {}
            XCTAssertTrue(handled)
            if let inputting = state as? InputState.Inputting {
                XCTAssertEqual(inputting.composingBuffer, "=")
            } else {
                XCTFail("State is not Inputting for =: \(state)")
            }
        }

        // 4. Shift + ' (") should output full-width double quote '”' and contain '；' in candidates
        do {
            handler.clear()
            var state: InputState = InputState.Empty()
            let input = KeyHandlerInput(
                inputText: "\"", keyCode: 39, charCode: charCode("\""), flags: .shift,
                isVerticalMode: false)
            let handled = handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {}
            XCTAssertTrue(handled)
            if let inputting = state as? InputState.Inputting {
                XCTAssertEqual(inputting.composingBuffer, "”")
            } else {
                XCTFail("State is not Inputting for Shift+': \(state)")
            }

            // Open candidate window using Space key (keyCode 49, charCode 32)
            let space = KeyHandlerInput(
                inputText: " ", keyCode: 49, charCode: 32, flags: [], isVerticalMode: false)
            handler.handle(input: space, state: state) { newState in
                state = newState
            } errorCallback: {}
            if let choosing = state as? InputState.ChoosingCandidate {
                XCTAssertEqual(choosing.candidates.first?.value, "”")
                XCTAssertTrue(choosing.candidates.contains(where: { $0.value == "；" }), "Candidate list must retain ；")
            }
        }

        // 5. Shift + 2~8 should output half-width symbols (@, #, $, %, ^, &, *)
        let shiftSymbols: [(String, String)] = [
            ("@", "@"), ("#", "#"), ("$", "$"), ("%", "%"),
            ("^", "^"), ("&", "&"), ("*", "*")
        ]
        for (sym, expected) in shiftSymbols {
            handler.clear()
            var state: InputState = InputState.Empty()
            let input = KeyHandlerInput(
                inputText: sym, keyCode: 0, charCode: charCode(sym), flags: .shift,
                isVerticalMode: false)
            let handled = handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {}
            XCTAssertTrue(handled, "Failed to handle symbol \(sym)")
            if let inputting = state as? InputState.Inputting {
                XCTAssertEqual(inputting.composingBuffer, expected, "Mismatch for symbol \(sym)")
            } else {
                XCTFail("State is not Inputting for Shift+\(sym): \(state)")
            }
        }

        // 6. Control + ; should output full-width semicolon '；'
        do {
            handler.clear()
            var state: InputState = InputState.Empty()
            let input = KeyHandlerInput(
                inputText: ";", keyCode: 41, charCode: charCode(";"), flags: .control,
                isVerticalMode: false)
            let handled = handler.handle(input: input, state: state) { newState in
                state = newState
            } errorCallback: {}
            XCTAssertTrue(handled)
            if let inputting = state as? InputState.Inputting {
                XCTAssertEqual(inputting.composingBuffer, "；")
            } else {
                XCTFail("State is not Inputting for Control+;: \(state)")
            }
        }
    }

    // MARK: - Dual-Track & Alphanumeric Short Tokens Tests (13 Verification Test Cases)
    func testAlphanumericShortTokens() {
        // Direct Phase 3 C++ Engine Guard: 4 + k must never invert into ㄜˋ (惡)
        do {
            handler.clear()
            var state: InputState = InputState.Empty()
            let key4 = KeyHandlerInput(inputText: "4", keyCode: 21, charCode: charCode("4"), flags: [], isVerticalMode: false)
            _ = handler.handle(input: key4, state: state) { newState in state = newState } errorCallback: {}

            let keyK = KeyHandlerInput(inputText: "k", keyCode: 40, charCode: charCode("k"), flags: [], isVerticalMode: false)
            _ = handler.handle(input: keyK, state: state) { newState in state = newState } errorCallback: {}

            let space = KeyHandlerInput(inputText: " ", keyCode: 49, charCode: 32, flags: [], isVerticalMode: false)
            _ = handler.handle(input: space, state: state) { newState in state = newState } errorCallback: {}

            if let committing = state as? InputState.Committing {
                XCTAssertNotEqual(committing.poppedText, "惡", "4 + k in KeyHandler must never invert into 惡")
            }
        }

        // Direct Phase 1 Engine Rules Tests
        do {
            let manager = WTFMixedInputManager.shared
            manager.clear()

            // Isolated tone rejection
            XCTAssertFalse(manager.validateBopomofo(input: "4").isValid, "Isolated tone 4 must not be valid Bopomofo")
            XCTAssertFalse(manager.validateBopomofo(input: "3").isValid, "Isolated tone 3 must not be valid Bopomofo")

            // Rule A: Isolated tone prefix collision
            XCTAssertTrue(manager.checkAlphanumericCollision(buffer: "4", nextChar: "k"), "Rule A: 4k collision")
            XCTAssertTrue(manager.checkAlphanumericCollision(buffer: "3", nextChar: "d"), "Rule A: 3d collision")
            XCTAssertTrue(manager.checkAlphanumericCollision(buffer: "3", nextChar: "c"), "Rule A: 3c collision")

            // Rule B: Digit-Bopomofo collision
            XCTAssertTrue(manager.checkAlphanumericCollision(buffer: "5", nextChar: "g"), "Rule B: 5g collision (ㄓ+ㄕ)")
            XCTAssertTrue(manager.checkAlphanumericCollision(buffer: "8", nextChar: "k"), "Rule B: 8k collision (ㄚ+ㄜ)")

            // Rule C: Letter followed by non-tone digit collision
            XCTAssertTrue(manager.checkAlphanumericCollision(buffer: "m", nextChar: "1"), "Rule C: m1 collision (ㄩ+ㄅ)")
            XCTAssertTrue(manager.checkAlphanumericCollision(buffer: "b", nextChar: "2"), "Rule C: b2 collision (ㄖ+ㄉ)")

            // Chinese preservation: Letter followed by valid tone digit must NOT collide
            XCTAssertFalse(manager.checkAlphanumericCollision(buffer: "m", nextChar: "4"), "m + 4 forms valid Chinese 玉")
            XCTAssertFalse(manager.checkAlphanumericCollision(buffer: "1u", nextChar: "4"), "1u + 4 forms valid Chinese 必")
            XCTAssertFalse(manager.checkAlphanumericCollision(buffer: "su", nextChar: "3"), "su + 3 forms valid Chinese 你")

            // Acronym resolution
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("4k"), "4K")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("3d"), "3D")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("3c"), "3C")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("5g"), "5G")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("8k"), "8K")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("m1"), "M1")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("m4"), "M4")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("ps5"), "PS5")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("b2b"), "B2B")
            XCTAssertEqual(WTFMixedInputManager.resolveCommittedEnglish("ai"), "AI")
        }

        // End-to-End Pipeline Verification with Mock Client
        class ShortTokenMockClient: NSObject, IMKTextInput {
            var insertedText: String = ""
            var markedText: String = ""

            func insertText(_ string: Any?, replacementRange: NSRange) {
                if let s = string as? String {
                    insertedText += s
                } else if let attr = string as? NSAttributedString {
                    insertedText += attr.string
                }
            }

            func setMarkedText(_ string: Any?, selectionRange: NSRange, replacementRange: NSRange) {
                if let s = string as? String {
                    markedText = s
                } else if let attr = string as? NSAttributedString {
                    markedText = attr.string
                }
            }

            func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
            func markedRange() -> NSRange { NSRange(location: 0, length: markedText.count) }
            func attributedSubstring(from range: NSRange) -> NSAttributedString? { nil }
            func length() -> Int { insertedText.count }
            func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int { 0 }
            func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]? { [:] }
            func validAttributesForMarkedText() -> [Any]? { [] }
            func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String?) {}
            func selectMode(_ modeIdentifier: String?) {}
            func supportsUnicode() -> Bool { true }
            func bundleIdentifier() -> String? { "test.bundle" }
            func windowLevel() -> CGWindowLevel { 0 }
            func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
            func uniqueClientIdentifierString() -> String? { "mock-id" }
            func string(from range: NSRange, actualRange: NSRangePointer?) -> String? { nil }
            func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer?) -> NSRect { NSRect.zero }
        }

        func keyCodeForChar(_ ch: Character) -> UInt16 {
            switch ch {
            case "a", "A": return 0
            case "s", "S": return 1
            case "d", "D": return 2
            case "f", "F": return 3
            case "h", "H": return 4
            case "g", "G": return 5
            case "z", "Z": return 6
            case "x", "X": return 7
            case "c", "C": return 8
            case "v", "V": return 9
            case "b", "B": return 11
            case "q", "Q": return 12
            case "w", "W": return 13
            case "e", "E": return 14
            case "r", "R": return 15
            case "y", "Y": return 16
            case "t", "T": return 17
            case "1": return 18
            case "2": return 19
            case "3": return 20
            case "4": return 21
            case "6": return 22
            case "5": return 23
            case "9": return 25
            case "7": return 26
            case "8": return 28
            case "0": return 29
            case "o", "O": return 31
            case "u", "U": return 32
            case "i", "I": return 34
            case "p", "P": return 35
            case "l", "L": return 37
            case "j", "J": return 38
            case "k", "K": return 40
            case ";": return 41
            case "m", "M": return 46
            case " ": return 49
            case "\t": return 48
            case "\r", "\n": return 36
            default: return 0
            }
        }

        func makeEvent(_ str: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            let ch = str.first ?? " "
            let code = (str == "\t") ? UInt16(48) : (str == " " ? UInt16(49) : keyCodeForChar(ch))
            return NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: str,
                charactersIgnoringModifiers: str.lowercased(),
                isARepeat: false,
                keyCode: code
            )!
        }

        func simulatePipeline(keys: [(String, NSEvent.ModifierFlags)]) -> String {
            WTFMixedInputManager.shared.clear()
            WTFMixedInputManager.shared.resetCommittedContext()
            let client = ShortTokenMockClient()
            let controller = McBopomofoInputMethodController(server: nil, delegate: nil, client: nil)!
            controller.activateServer(client)

            for (key, flags) in keys {
                let event = makeEvent(key, flags: flags)
                _ = controller.handle(event, client: client)
            }
            let text = client.insertedText.isEmpty ? client.markedText : client.insertedText
            return text.trimmingCharacters(in: .whitespaces)
        }

        // 1. 4 -> k -> Space => 4K (prohibit Chinese 惡)
        let res1 = simulatePipeline(keys: [("4", []), ("k", []), (" ", [])])
        XCTAssertEqual(res1, "4K", "Case 1: 4 -> k -> Space must yield 4K and prohibit 惡")

        // 2. 3 -> d -> Space => 3D (prohibit Chinese 渴 / 可)
        let res2 = simulatePipeline(keys: [("3", []), ("d", []), (" ", [])])
        XCTAssertEqual(res2, "3D", "Case 2: 3 -> d -> Space must yield 3D and prohibit 渴/可")

        // 3. 3 -> c -> Space => 3C (prohibit Chinese 好 / 虎)
        let res3 = simulatePipeline(keys: [("3", []), ("c", []), (" ", [])])
        XCTAssertEqual(res3, "3C", "Case 3: 3 -> c -> Space must yield 3C and prohibit 好/虎")

        // 4. 5 -> g -> Space => 5G (prohibit g(ㄕ) overwriting 5(ㄓ))
        let res4 = simulatePipeline(keys: [("5", []), ("g", []), (" ", [])])
        XCTAssertEqual(res4, "5G", "Case 4: 5 -> g -> Space must yield 5G")

        // 5. 8 -> k -> Space => 8K (prohibit k(ㄜ) overwriting 8(ㄚ))
        let res5 = simulatePipeline(keys: [("8", []), ("k", []), (" ", [])])
        XCTAssertEqual(res5, "8K", "Case 5: 8 -> k -> Space must yield 8K")

        // 6. m -> 1 -> Space => M1 (prohibit Mㄅ)
        let res6 = simulatePipeline(keys: [("m", []), ("1", []), (" ", [])])
        XCTAssertEqual(res6, "M1", "Case 6: m -> 1 -> Space must yield M1")

        // 7. Shift+M -> 4 -> Space => M4
        let res7 = simulatePipeline(keys: [("M", .shift), ("4", []), (" ", [])])
        XCTAssertEqual(res7, "M4", "Case 7: Shift+M -> 4 -> Space must yield M4")

        // 8. p -> s -> 5 -> Space => PS5 / ps5
        let res8 = simulatePipeline(keys: [("p", []), ("s", []), ("5", []), (" ", [])])
        XCTAssertTrue(res8 == "PS5" || res8 == "ps5", "Case 8: p -> s -> 5 -> Space must yield PS5 or ps5, got: \(res8)")

        // 9. b -> 2 -> b -> Space => B2B / b2b
        let res9 = simulatePipeline(keys: [("b", []), ("2", []), ("b", []), (" ", [])])
        XCTAssertTrue(res9 == "B2B" || res9 == "b2b", "Case 9: b -> 2 -> b -> Space must yield B2B or b2b, got: \(res9)")

        // 10. a -> i -> Tab => AI
        let res10 = simulatePipeline(keys: [("a", []), ("i", []), ("\t", [])])
        XCTAssertEqual(res10, "AI", "Case 10: a -> i -> Tab must yield AI")

        // 11. m -> 4 -> Space => Chinese 玉 (or homophone)
        let res11 = simulatePipeline(keys: [("m", []), ("4", []), (" ", [])])
        XCTAssertNotEqual(res11, "M4", "Case 11: m -> 4 -> Space must NOT be M4")
        XCTAssertFalse(res11.isEmpty, "Case 11: m -> 4 -> Space must yield Chinese character")
        XCTAssertTrue(WTFMixedInputManager.isCJK(res11.first ?? " "), "Case 11: m -> 4 -> Space must output Chinese, got: \(res11)")

        // 12. 1 -> u -> 4 -> Space => Chinese 必 (or homophone)
        let res12 = simulatePipeline(keys: [("1", []), ("u", []), ("4", []), (" ", [])])
        XCTAssertFalse(res12.isEmpty, "Case 12: 1 -> u -> 4 -> Space must yield Chinese character")
        XCTAssertTrue(WTFMixedInputManager.isCJK(res12.first ?? " "), "Case 12: 1 -> u -> 4 -> Space must output Chinese, got: \(res12)")

        // 13. s -> u -> 3 -> Space => Chinese 你
        let res13 = simulatePipeline(keys: [("s", []), ("u", []), ("3", []), (" ", [])])
        XCTAssertEqual(res13, "你", "Case 13: s -> u -> 3 -> Space must yield Chinese 你, got: \(res13)")
    }

    // MARK: - Continuous Chinese Sentences & Final Digits Regression Tests (S1 ~ S7)
    func testContinuousChineseSentencesAndFinalDigits() {
        class ShortTokenMockClient: NSObject, IMKTextInput {
            var insertedText: String = ""
            var markedText: String = ""

            func insertText(_ string: Any?, replacementRange: NSRange) {
                if let s = string as? String {
                    insertedText += s
                } else if let attr = string as? NSAttributedString {
                    insertedText += attr.string
                }
            }

            func setMarkedText(_ string: Any?, selectionRange: NSRange, replacementRange: NSRange) {
                if let s = string as? String {
                    markedText = s
                } else if let attr = string as? NSAttributedString {
                    markedText = attr.string
                }
            }

            func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
            func markedRange() -> NSRange { NSRange(location: 0, length: markedText.count) }
            func attributedSubstring(from range: NSRange) -> NSAttributedString? { nil }
            func length() -> Int { insertedText.count }
            func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int { 0 }
            func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>?) -> [AnyHashable: Any]? { [:] }
            func validAttributesForMarkedText() -> [Any]? { [] }
            func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String?) {}
            func selectMode(_ modeIdentifier: String?) {}
            func supportsUnicode() -> Bool { true }
            func bundleIdentifier() -> String? { "test.bundle" }
            func windowLevel() -> CGWindowLevel { 0 }
            func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
            func uniqueClientIdentifierString() -> String? { "mock-id" }
            func string(from range: NSRange, actualRange: NSRangePointer?) -> String? { nil }
            func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer?) -> NSRect { NSRect.zero }
        }

        func keyCodeForChar(_ ch: Character) -> UInt16 {
            switch ch {
            case "a", "A": return 0
            case "s", "S": return 1
            case "d", "D": return 2
            case "f", "F": return 3
            case "h", "H": return 4
            case "g", "G": return 5
            case "z", "Z": return 6
            case "x", "X": return 7
            case "c", "C": return 8
            case "v", "V": return 9
            case "b", "B": return 11
            case "q", "Q": return 12
            case "w", "W": return 13
            case "e", "E": return 14
            case "r", "R": return 15
            case "y", "Y": return 16
            case "t", "T": return 17
            case "1": return 18
            case "2": return 19
            case "3": return 20
            case "4": return 21
            case "6": return 22
            case "5": return 23
            case "9": return 25
            case "7": return 26
            case "8": return 28
            case "0": return 29
            case "o", "O": return 31
            case "u", "U": return 32
            case "i", "I": return 34
            case "p", "P": return 35
            case "l", "L": return 37
            case "j", "J": return 38
            case "k", "K": return 40
            case ";": return 41
            case "m", "M": return 46
            case " ": return 49
            case "\t": return 48
            case "\r", "\n": return 36
            default: return 0
            }
        }

        func makeEvent(_ str: String, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            let ch = str.first ?? " "
            let code = (str == "\t") ? UInt16(48) : (str == " " ? UInt16(49) : keyCodeForChar(ch))
            return NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: str,
                charactersIgnoringModifiers: str.lowercased(),
                isARepeat: false,
                keyCode: code
            )!
        }

        func simulatePipeline(keys: [(String, NSEvent.ModifierFlags)]) -> String {
            WTFMixedInputManager.shared.clear()
            WTFMixedInputManager.shared.resetCommittedContext()
            let client = ShortTokenMockClient()
            let controller = McBopomofoInputMethodController(server: nil, delegate: nil, client: nil)!
            controller.activateServer(client)

            for (key, flags) in keys {
                let event = makeEvent(key, flags: flags)
                _ = controller.handle(event, client: client)
            }
            let text = client.insertedText.isEmpty ? client.markedText : client.insertedText
            return text.trimmingCharacters(in: .whitespaces)
        }

        // S1: 含 8(ㄚ) 韻母單字: w -> 8 -> Space => 「他」（或同音字）
        let resS1 = simulatePipeline(keys: [("w", []), ("8", []), (" ", [])])
        XCTAssertTrue(WTFMixedInputManager.isCJK(resS1.first ?? " "), "S1 must yield Chinese 他, got: \(resS1)")
        XCTAssertFalse(resS1.contains("w8"), "S1 must not yield w8")
        XCTAssertFalse(resS1.contains(" "), "S1 must not contain spaces")

        // S2: 含 9(ㄞ) 韻母單字: e -> j -> 9 -> 4 -> Enter => 「怪」
        let resS2 = simulatePipeline(keys: [("e", []), ("j", []), ("9", []), ("4", []), ("\n", [])])
        XCTAssertEqual(resS2, "怪", "S2 must yield 怪, got: \(resS2)")
        XCTAssertFalse(resS2.contains(" "), "S2 must not contain spaces")

        // S3: 含 0(ㄢ) 韻母單字: d -> 0 -> 4 -> Enter => 「看」
        let resS3 = simulatePipeline(keys: [("d", []), ("0", []), ("4", []), ("\n", [])])
        XCTAssertEqual(resS3, "看", "S3 must yield 看, got: \(resS3)")
        XCTAssertFalse(resS3.contains(" "), "S3 must not contain spaces")

        // S4: 雙字連打（前字 4 聲 ＋ 後字字母起首）: 5k4 (這) -> u;4 (樣) -> Enter => 「這樣」
        let resS4 = simulatePipeline(keys: [("5", []), ("k", []), ("4", []), ("u", []), (";", []), ("4", []), ("\n", [])])
        XCTAssertEqual(resS4, "這樣", "S4 must yield 這樣, got: \(resS4)")
        XCTAssertFalse(resS4.contains(" "), "S4 must not contain spaces")
        XCTAssertFalse(resS4.contains("4u"), "S4 must not trigger Rule A 4u collision")

        // S5: 雙字連打（後字含 9 韻母）: fu6 (奇) -> ej94 (怪) -> Enter => 「奇怪」
        let resS5 = simulatePipeline(keys: [("f", []), ("u", []), ("6", []), ("e", []), ("j", []), ("9", []), ("4", []), ("\n", [])])
        XCTAssertEqual(resS5, "奇怪", "S5 must yield 奇怪, got: \(resS5)")
        XCTAssertFalse(resS5.contains(" "), "S5 must not contain spaces")

        // S6: 雙字連打（後字為數字聲母 2 起首）: cl3 (好) -> 283 (打) -> Enter => 「好打」
        let resS6 = simulatePipeline(keys: [("c", []), ("l", []), ("3", []), ("2", []), ("8", []), ("3", []), ("\n", [])])
        XCTAssertEqual(resS6, "好打", "S6 must yield 好打, got: \(resS6)")
        XCTAssertFalse(resS6.contains(" "), "S6 must not contain spaces")

        // S7: 使用者實測崩潰完整長句還原
        // 句 1: 這樣對嗎 (5k4 u;4 2jo4 a87 Enter)
        let s7Keys1: [(String, NSEvent.ModifierFlags)] = [
            ("5", []), ("k", []), ("4", []),
            ("u", []), (";", []), ("4", []),
            ("2", []), ("j", []), ("o", []), ("4", []),
            ("a", []), ("8", []), ("7", []),
            ("\n", [])
        ]
        let resS7_1 = simulatePipeline(keys: s7Keys1)
        XCTAssertEqual(resS7_1, "這樣對嗎", "S7_1 must yield 這樣對嗎 without spaces, got: \(resS7_1)")
        XCTAssertFalse(resS7_1.contains(" "), "S7_1 must not contain spaces")

        // 句 2: 打出來的字很奇怪 (283 tjSpace x96 2k7 y4 cp3 fu6 ej94 Enter)
        let s7Keys2: [(String, NSEvent.ModifierFlags)] = [
            ("2", []), ("8", []), ("3", []),
            ("t", []), ("j", []), (" ", []),
            ("x", []), ("9", []), ("6", []),
            ("2", []), ("k", []), ("7", []),
            ("y", []), ("4", []),
            ("c", []), ("p", []), ("3", []),
            ("f", []), ("u", []), ("6", []),
            ("e", []), ("j", []), ("9", []), ("4", []),
            ("\n", [])
        ]
        let resS7_2 = simulatePipeline(keys: s7Keys2)
        XCTAssertTrue(resS7_2 == "打出來的字很奇怪" || resS7_2 == "打出來的自很奇怪", "S7_2 must yield 打出來的字很奇怪 (or 自) without spaces, got: \(resS7_2)")
        XCTAssertFalse(resS7_2.contains(" "), "S7_2 must not contain spaces")
    }
}

