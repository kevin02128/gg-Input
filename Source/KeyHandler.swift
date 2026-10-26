import Foundation
import SwiftEngine
import CandidateUI
import OpenCCBridge
import ChineseNumbers
import RomanNumbers
import BopomofoBraille

// MARK: - InputMode
struct InputMode: RawRepresentable, Equatable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    var rawValue: String

    init(rawValue: String) {
        if rawValue.hasSuffix("PlainBopomofo") || rawValue == "PlainBopomofo" {
            self.rawValue = "com.kevin.inputmethod.gg.PlainBopomofo"
        } else {
            self.rawValue = "com.kevin.inputmethod.gg.Bopomofo"
        }
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    var description: String { rawValue }

    static let bopomofo = InputMode("com.kevin.inputmethod.gg.Bopomofo")
    static let plainBopomofo = InputMode("com.kevin.inputmethod.gg.PlainBopomofo")
}

let InputModeBopomofo: InputMode = .bopomofo
let InputModePlainBopomofo: InputMode = .plainBopomofo

// MARK: - KeyHandlerDelegate
@objc(KeyHandlerDelegate)
protocol KeyHandlerDelegate: AnyObject {
    func candidateController(for keyHandler: KeyHandler) -> Any
    func keyHandler(_ keyHandler: KeyHandler, didSelectCandidateAt index: Int, candidateController: Any)
    func keyHandler(_ keyHandler: KeyHandler, didRequestWriteUserPhraseWith state: InputState) -> Bool
    func keyHandler(_ keyHandler: KeyHandler, didRequestBoostScoreForPhrase phrase: String, reading: String) -> Bool
    func keyHandler(_ keyHandler: KeyHandler, didRequestExcludePhrase phrase: String, reading: String) -> Bool
    func keyHandlerDidRequestReloadLanguageModel(_ keyHandler: KeyHandler) -> Bool
}

// MARK: - BuildAssociatedPhraseParams
@objc(BuildAssociatedPhraseParams)
final class BuildAssociatedPhraseParams: NSObject {
    @objc var previousState: Any?
    @objc var prefixCursorIndex: Int = 0
    @objc var reading: String = ""
    @objc var value: String = ""
    @objc var candidateIndex: Int = 0
    @objc var useVerticalMode: Bool = false
    @objc var autoTriggered: Bool = false
}

// MARK: - KeyHandler
@objc(KeyHandler)
final class KeyHandler: NSObject {
    weak var delegate: KeyHandlerDelegate?

    private var bpmfReadingBuffer = BopomofoBuffer()
    private var grid: ReadingGrid
    private var latestWalk = ReadingGrid.WalkResult()
    private(set) var gridRevision: UInt64 = 0

    private var _inputMode: InputMode = .bopomofo
    private var languageModel: EngineLM

    override init() {
        if !LanguageModelManager.engineMcBopomofo.isDataModelLoaded {
            LanguageModelManager.loadDataModel(.bopomofo)
        }
        self.languageModel = LanguageModelManager.engineMcBopomofo
        self.grid = ReadingGrid(languageModel: self.languageModel)
        self.grid.readingSeparator = "-"
        super.init()
    }

    var inputMode: InputMode {
        get { _inputMode }
        set {
            let newInputMode = newValue
            let newLM: EngineLM
            if newInputMode == .plainBopomofo {
                if !LanguageModelManager.enginePlainBopomofo.isDataModelLoaded {
                    LanguageModelManager.loadDataModel(.plainBopomofo)
                }
                newLM = LanguageModelManager.enginePlainBopomofo
                newLM.phraseReplacementEnabled = false
            } else {
                if !LanguageModelManager.engineMcBopomofo.isDataModelLoaded {
                    LanguageModelManager.loadDataModel(.bopomofo)
                }
                newLM = LanguageModelManager.engineMcBopomofo
                newLM.phraseReplacementEnabled = Preferences.phraseReplacementEnabled
            }
            newLM.externalConverterEnabled = (Preferences.chineseConversionStyle == .model)

            if _inputMode != newInputMode {
                _inputMode = newInputMode
                languageModel = newLM
                grid = ReadingGrid(languageModel: languageModel)
                grid.readingSeparator = "-"
                bpmfReadingBuffer.clear()
            }
        }
    }

    func syncWithPreferences() {
        // Keyboard layout in Standard Daqian is standard
    }

    func clear() {
        bpmfReadingBuffer.clear()
        grid.clear()
        latestWalk = ReadingGrid.WalkResult()
        gridRevision &+= 1
    }

    var cursorIndex: Int {
        grid.cursor
    }

    var actualCandidateCursorIndex: Int {
        computeActualCursorIndex(grid.cursor)
    }

    func computeActualCursorIndex(_ cursor: Int) -> Int {
        if cursor == grid.length && cursor > 0 {
            return cursor - 1
        }
        if !Preferences.selectPhraseAfterCursorAsCandidate && cursor > 0 {
            return cursor - 1
        }
        return cursor
    }

    func currentBpmfReading() -> String {
        bpmfReadingBuffer.composedString
    }

    func hasUnconfirmedReading() -> Bool {
        !bpmfReadingBuffer.isEmpty
    }

    func clearUnconfirmedReading() {
        bpmfReadingBuffer.clear()
    }

    func isValidReadingKey(_ charCode: Int8) -> Bool {
        bpmfReadingBuffer.isValidKey(charCode: Int(charCode))
    }

    func isValidReadingKey(charCode: Int) -> Bool {
        bpmfReadingBuffer.isValidKey(charCode: charCode)
    }

    func isValidReadingKey(_ charCode: Int) -> Bool {
        bpmfReadingBuffer.isValidKey(charCode: charCode)
    }

    private func currentLayout() -> String {
        Preferences.keyboardLayoutName + "_"
    }

    private func walk() {
        latestWalk = grid.walk()
        gridRevision &+= 1
    }

    private var currentReadings: [String] {
        grid.readings
    }

    // MARK: - Force Commit
    @objc(handleForceCommitWithStateCallback:)
    func handleForceCommit(stateCallback: (InputState) -> Void) {
        if bpmfReadingBuffer.isEmpty && grid.length == 0 {
            return
        }
        if let inputting = buildInputtingState() as? InputState.Inputting {
            clear()
            stateCallback(InputState.Committing(poppedText: inputting.composingBuffer))
        }
    }

    // MARK: - State Construction
    @objc func buildInputtingState() -> InputState {
        var runningCursor = 0
        var composed = ""
        let builderCursor = grid.cursor
        var composedCursor = 0
        var tooltip = ""

        var bopomofoAnnotationUsed = false
        var bopomofoAnnotationHasPUAs = false
        var bopomofoAnnotationHasVariants = false

        for node in latestWalk.nodes {
            let value = node.value
            var composedValueLength = value.utf8.count

            var nodeHasBopomofoAnnotation = false
            var nodeAnnotationResult: (annotatedString: String, hasVariants: Bool, hasPUAs: Bool, accumulatedLengths: [Int]) = ("", false, false, [])

            if !Preferences.bopomofoFontAnnotationSupportEnabled || _inputMode == .plainBopomofo {
                composed += value
            } else if !LanguageModelManager.engineMcBopomofo.isVariantAnnotatorLoaded {
                composed += value
            } else {
                let cpCount = value.count
                if cpCount != node.spanningLength {
                    composed += value
                } else {
                    let chars = value.map { String($0) }
                    let readings = node.reading.split(separator: "-").map { String($0) }
                    if readings.count != cpCount {
                        composed += value
                    } else {
                        nodeAnnotationResult = LanguageModelManager.engineMcBopomofo.annotateVariant(characters: chars, readings: readings)
                        nodeHasBopomofoAnnotation = true
                        bopomofoAnnotationUsed = true
                        bopomofoAnnotationHasPUAs = bopomofoAnnotationHasPUAs || nodeAnnotationResult.hasPUAs
                        bopomofoAnnotationHasVariants = bopomofoAnnotationHasVariants || nodeAnnotationResult.hasVariants
                        composed += nodeAnnotationResult.annotatedString
                        composedValueLength = nodeAnnotationResult.annotatedString.utf8.count
                    }
                }
            }

            if runningCursor == builderCursor {
                continue
            }

            let readingLength = node.spanningLength
            if runningCursor + readingLength <= builderCursor {
                composedCursor += composedValueLength
                runningCursor += readingLength
                continue
            }

            let distance = builderCursor - runningCursor
            let valueCodePointCount = value.count
            let cpLen = min(distance, valueCodePointCount)
            let actualValue = String(value.prefix(cpLen))

            if nodeHasBopomofoAnnotation {
                if cpLen < nodeAnnotationResult.accumulatedLengths.count {
                    composedCursor += nodeAnnotationResult.accumulatedLengths[cpLen]
                } else {
                    composedCursor += actualValue.utf8.count
                }
            } else {
                composedCursor += actualValue.utf8.count
            }
            runningCursor += distance

            if valueCodePointCount != readingLength {
                if builderCursor > 0 && builderCursor < grid.readings.count {
                    let prevReading = grid.readings[builderCursor - 1]
                    let nextReading = grid.readings[builderCursor]
                    tooltip = String(format: NSLocalizedString("Cursor is between \"%@\" and \"%@\".", comment: ""), prevReading, nextReading)
                }
            }
        }

        if bopomofoAnnotationUsed {
            var annotationTooltip = NSLocalizedString("Bopomofo annotation support on", comment: "")
            if bopomofoAnnotationHasVariants && bopomofoAnnotationHasPUAs {
                annotationTooltip = NSLocalizedString("Bopomofo annotation: variant selectors and PUA blocks in text", comment: "")
            } else if bopomofoAnnotationHasVariants {
                annotationTooltip = NSLocalizedString("Bopomofo annotation: variant selectors in text", comment: "")
            } else if bopomofoAnnotationHasPUAs {
                annotationTooltip = NSLocalizedString("Bopomofo annotation: PUA blocks in text", comment: "")
            }

            if !tooltip.isEmpty {
                tooltip = "\(tooltip) / \(annotationTooltip)"
            } else {
                tooltip = annotationTooltip
            }
        }

        let utf8Composed = Array(composed.utf8)
        let headBytes = utf8Composed.prefix(min(composedCursor, utf8Composed.count))
        let tailBytes = utf8Composed.dropFirst(min(composedCursor, utf8Composed.count))

        let head = String(decoding: headBytes, as: UTF8.self)
        let reading = bpmfReadingBuffer.composedString
        let tail = String(decoding: tailBytes, as: UTF8.self)

        let composedText = head + reading + tail
        let cursorIdx = head.utf16.count + reading.utf16.count

        let newState = InputState.Inputting(composingBuffer: composedText, cursorIndex: UInt(cursorIdx))
        newState.tooltip = tooltip
        return newState
    }

    private func buildCandidateState(from inputting: InputState.Inputting, useVerticalMode: Bool) -> InputState.ChoosingCandidate {
        let candidates = grid.candidatesAt(loc: actualCandidateCursorIndex)
        var valueCountMap: [String: Int] = [:]
        for c in candidates {
            valueCountMap[c.value, default: 0] += 1
        }

        var candidatesArray: [InputState.Candidate] = []
        for c in candidates {
            var displayText = c.value
            if (valueCountMap[displayText] ?? 0) > 1 {
                displayText += " (" + c.reading.replacingOccurrences(of: "-", with: " ") + ")"
            }
            let candidate = InputState.Candidate(
                reading: c.reading,
                value: c.value,
                displayText: displayText,
                rawValue: c.rawValue
            )
            candidatesArray.append(candidate)
        }

        return InputState.ChoosingCandidate(
            composingBuffer: inputting.composingBuffer,
            cursorIndex: inputting.cursorIndex,
            candidates: candidatesArray,
            useVerticalMode: useVerticalMode
        )
    }

    private func inputtingStateWithMarkingUnsupportedTooltip(_ state: InputState.Inputting) -> InputState.Inputting {
        let updated = InputState.Inputting(composingBuffer: state.composingBuffer, cursorIndex: state.cursorIndex)
        updated.tooltip = NSLocalizedString("Cannot add new phrases when Bopomofo annotation is on", comment: "")
        return updated
    }

    // MARK: - Node Fixing
    @objc(fixNodeWithReading:value:originalCursorIndex:useMoveCursorAfterSelectionSetting:)
    func fixNode(reading: String, value: String, originalCursorIndex: Int, useMoveCursorAfterSelectionSetting flag: Bool) {
        let prevWalk = latestWalk.copyWithFixedNodes()
        let actualCursor = actualCandidateCursorIndex

        let candidate = ReadingGrid.Candidate(reading: reading, value: value)
        guard grid.overrideCandidate(loc: actualCursor, candidate: candidate) else {
            return
        }

        walk()

        var accumulatedCursor: Int? = nil
        if let currentNodeIdx = latestWalk.findNodeAt(cursor: actualCursor, outCursorPastNode: &accumulatedCursor) {
            let currentNode = latestWalk.nodes[currentNodeIdx]
            if currentNode.currentUnigram.score > -8.0 {
                LanguageModelManager.userOverrideModel.observe(
                    walkBefore: prevWalk,
                    walkAfter: latestWalk,
                    cursor: actualCursor,
                    timestamp: Date().timeIntervalSince1970
                )
            }

            if flag && Preferences.moveCursorAfterSelectingCandidate, let acc = accumulatedCursor {
                grid.setCursor(acc)
            } else {
                grid.setCursor(originalCursorIndex)
            }
        } else {
            grid.setCursor(originalCursorIndex)
        }
    }

    @objc(fixNodeForAssociatedPhraseWithPrefixAt:prefixReading:prefixValue:associatedPhraseReading:associatedPhraseValue:)
    func fixNodeForAssociatedPhraseWithPrefix(at prefixCursorIndex: Int, prefixReading: String, prefixValue: String, associatedPhraseReading: String, associatedPhraseValue: String) {
        if grid.length == 0 {
            return
        }
        let actualPrefixCursorIndex = (prefixCursorIndex == grid.length) ? prefixCursorIndex - 1 : prefixCursorIndex

        var accumulatedCursor: Int? = nil
        guard let nodeIdx = latestWalk.findNodeAt(cursor: actualPrefixCursorIndex, outCursorPastNode: &accumulatedCursor),
              let accCursor = accumulatedCursor else {
            return
        }

        let targetNode = latestWalk.nodes[nodeIdx]
        if accCursor < targetNode.spanningLength {
            return
        }

        let originalNodeValues = targetNode.value.map { String($0) }
        if originalNodeValues.count == targetNode.spanningLength {
            var overrideIdx = accCursor - targetNode.spanningLength
            for val in originalNodeValues {
                grid.overrideCandidate(loc: overrideIdx, candidateValue: val)
                overrideIdx += 1
            }
        }

        let prefixCandidate = ReadingGrid.Candidate(reading: prefixReading, value: prefixValue)
        guard grid.overrideCandidate(loc: actualPrefixCursorIndex, candidate: prefixCandidate) else {
            return
        }
        walk()

        var postAccCursor: Int? = nil
        guard let postNodeIdx = latestWalk.findNodeAt(cursor: actualPrefixCursorIndex, outCursorPastNode: &postAccCursor),
              var runningAcc = postAccCursor else {
            return
        }
        grid.setCursor(runningAcc)

        let assocValues = associatedPhraseValue.map { String($0) }
        let nodeSpanningLen = latestWalk.nodes[postNodeIdx].spanningLength
        let splitReadings = associatedPhraseReading.split(separator: "-").map { String($0) }
        if nodeSpanningLen >= splitReadings.count {
            return
        }

        for i in nodeSpanningLen..<splitReadings.count {
            _ = grid.insertReading(splitReadings[i])
            runningAcc += 1
            if i < assocValues.count {
                grid.overrideCandidate(loc: runningAcc, candidateValue: assocValues[i])
            }
            grid.setCursor(runningAcc)
        }

        _ = grid.overrideCandidate(loc: actualPrefixCursorIndex, candidateValue: associatedPhraseValue)
        walk()
    }

    // MARK: - Associated Phrases
    @objc(buildAssociatedPhrasePlainStateWithReading:value:useVerticalMode:)
    func buildAssociatedPhrasePlainState(withReading reading: String, value: String, useVerticalMode: Bool) -> InputState? {
        var actualVal = value
        if Preferences.chineseConversionEnabled && Preferences.chineseConversionStyle == .model {
            actualVal = OpenCCBridge.shared.convertToTraditional(value) ?? value
        }

        let readings = reading.split(separator: "-").map { String($0) }
        let phrases = languageModel.findAssociatedPhrases(prefixValue: actualVal, prefixReadings: readings)
        guard !phrases.isEmpty else { return nil }

        var candidates: [InputState.Candidate] = []
        for p in phrases {
            let valWithoutPrefix = String(p.value.dropFirst(actualVal.count))
            let readingsWithoutPrefix = Array(p.readings.dropFirst(readings.count))
            let combinedReading = readingsWithoutPrefix.joined(separator: "-")

            let c = InputState.Candidate(
                reading: combinedReading,
                value: valWithoutPrefix,
                displayText: valWithoutPrefix,
                rawValue: valWithoutPrefix
            )
            candidates.append(c)
        }

        return InputState.AssociatedPhrasesPlain(candidates: candidates, useVerticalMode: useVerticalMode)
    }

    @objc(buildAssociatedPhraseStateWithParams:)
    func buildAssociatedPhraseState(with params: BuildAssociatedPhraseParams) -> InputState? {
        var actualVal = params.value
        let scToTc = Preferences.chineseConversionEnabled && Preferences.chineseConversionStyle == .model
        if scToTc {
            actualVal = OpenCCBridge.shared.convertToTraditional(actualVal) ?? actualVal
        }

        let readings = params.reading.split(separator: "-").map { String($0) }
        let phrases = languageModel.findAssociatedPhrases(prefixValue: actualVal, prefixReadings: readings)
        guard !phrases.isEmpty else { return nil }

        var candidates: [InputState.Candidate] = []
        for p in phrases {
            let combinedReading = p.combinedReading
            var val = p.value
            let valWithoutPrefix = String(p.value.dropFirst(actualVal.count))
            var displayText = valWithoutPrefix

            if scToTc {
                val = OpenCCBridge.shared.convertToSimplified(val) ?? val
                displayText = OpenCCBridge.shared.convertToSimplified(displayText) ?? displayText
            }

            let c = InputState.Candidate(
                reading: combinedReading,
                value: val,
                displayText: displayText,
                rawValue: val
            )
            candidates.append(c)
        }

        guard let prev = (params.previousState as? InputState.NotEmpty) ?? (buildInputtingState() as? InputState.NotEmpty) else {
            return nil
        }

        return InputState.AssociatedPhrases(
            previousState: prev,
            prefixCursorIndex: params.prefixCursorIndex,
            prefixReading: params.reading,
            prefixValue: params.value,
            selectedIndex: params.candidateIndex,
            candidates: candidates,
            useVerticalMode: params.useVerticalMode,
            autoTriggered: params.autoTriggered
        )
    }

    @objc(findTopAssociatedPhraseSuffixForPrefix:)
    func findTopAssociatedPhraseSuffix(for prefix: String) -> String? {
        guard !prefix.isEmpty, languageModel.isAssociatedPhrasesLoaded else { return nil }
        guard let reading = languageModel.getReading(for: prefix) else { return nil }
        let readings = reading.split(separator: "-").map { String($0) }
        let phrases = languageModel.findAssociatedPhrases(prefixValue: prefix, prefixReadings: readings)
        guard let first = phrases.first, first.value.count > prefix.count else { return nil }

        let suffix = String(first.value.dropFirst(prefix.count))
        guard !suffix.isEmpty else { return nil }
        let range = suffix.rangeOfComposedCharacterSequence(at: suffix.startIndex)
        return String(suffix[range])
    }

    @discardableResult
    @objc(handleAssociatedPhraseWithState:useVerticalMode:stateCallback:errorCallback:autoTriggered:maxCandidateCount:)
    func handleAssociatedPhrase(with state: InputState, useVerticalMode: Bool, stateCallback: (InputState) -> Void, errorCallback: () -> Void, autoTriggered: Bool, maxCandidateCount: Int) -> Bool {
        let cursor = grid.cursor
        guard cursor >= 1 else {
            errorCallback()
            return true
        }

        let prefixCursorIndex = cursor - 1
        var endCursorIndex: Int? = nil
        guard let nodeIdx = latestWalk.findNodeAt(cursor: prefixCursorIndex, outCursorPastNode: &endCursorIndex),
              let endCursor = endCursorIndex, endCursor > 0 else {
            errorCallback()
            return true
        }

        let targetNode = latestWalk.nodes[nodeIdx]
        let codepoints = targetNode.value.map { String($0) }
        let readings = targetNode.reading.split(separator: "-").map { String($0) }
        guard codepoints.count == readings.count, endCursor >= readings.count else {
            errorCallback()
            return true
        }

        let startCursorIndex = endCursor - readings.count
        let maxPrefixLen = cursor - startCursorIndex

        for prefixLen in stride(from: maxPrefixLen, through: 1, by: -1) {
            let startIdx = maxPrefixLen - prefixLen
            let cpSlice = codepoints[startIdx..<maxPrefixLen]
            let rdSlice = readings[startIdx..<maxPrefixLen]

            let val = cpSlice.joined()
            let combinedReading = rdSlice.joined(separator: "-")

            let params = BuildAssociatedPhraseParams()
            params.previousState = state
            params.prefixCursorIndex = prefixCursorIndex
            params.reading = combinedReading
            params.value = val
            params.candidateIndex = 0
            params.useVerticalMode = useVerticalMode
            params.autoTriggered = autoTriggered

            if let newState = buildAssociatedPhraseState(with: params) {
                stateCallback(newState)
                return true
            }
        }

        if !autoTriggered {
            errorCallback()
        }
        return true
    }

    func collectUserFileIssues() -> [String] {
        var result: [String] = []
        let issues = languageModel.getUserFileIssues()
        for issue in issues {
            var msg = ""
            switch issue.fileType {
            case .userPhrases:
                msg += NSLocalizedString("User phrase file", comment: "")
            case .excludedPhrases:
                msg += NSLocalizedString("Excluded phrase file", comment: "")
            case .phraseReplacementMap:
                msg += NSLocalizedString("Phrase replacement file", comment: "")
            }

            let filename = (issue.path as NSString).lastPathComponent
            msg += " (\(filename)) "
            msg += String(format: NSLocalizedString("line %lu: ", comment: ""), issue.lineNumber)

            switch issue.issueType {
            case .missingSecondColumn:
                msg += NSLocalizedString("Only one column was found.", comment: "")
            case .nullCharacterInText:
                msg += NSLocalizedString("Illegal NULL character was found.", comment: "")
            }
            result.append(msg)
        }
        return result
    }

    // MARK: - Keystroke Handlers
    private func currentHanyuPinyin() -> String {
        var array: [String] = []
        for node in latestWalk.nodes {
            let key = node.reading
            let val = node.value
            if key.hasPrefix("_") {
                array.append(val)
            } else {
                let parts = key.split(separator: "-")
                for p in parts {
                    let syllable = BopomofoSyllable.fromComposed(string: String(p))
                    array.append(syllable.toHanyuPinyin())
                }
            }
        }
        return array.joined()
    }

    private func currentHtmlRuby() -> String {
        var composed = ""
        for node in latestWalk.nodes {
            var key = node.reading
            key = key.replacingOccurrences(of: "-", with: " ")
            let val = node.value
            if key.hasPrefix("_") {
                composed += val
            } else {
                composed += "<ruby>\(val)<rp>(</rp><rt>\(key)</rt><rp>)</rp></ruby>"
            }
        }
        return composed
    }

    private func currentBraille(type: BrailleType) -> String {
        var composing = ""
        for node in latestWalk.nodes {
            let val = node.currentUnigram.value
            let reading = node.reading
            if reading.hasPrefix("_") {
                composing += BopomofoBrailleConverter.convert(bopomofo: val, type: type)
            } else {
                let parts = reading.split(separator: "-")
                for p in parts {
                    composing += BopomofoBrailleConverter.convert(bopomofo: String(p), type: type)
                }
            }
        }
        return composing
    }

    private func currentBpmfReadingString() -> String {
        currentReadings.joined(separator: "-")
    }

    // MARK: - Main Handle Entrypoint
    @objc(handleInput:state:stateCallback:errorCallback:)
    func handle(input: KeyHandlerInput, state inState: InputState, stateCallback: @escaping (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        var state = inState
        let charCode = Int(input.charCode)

        // Selecting feature / Date macro
        if state is InputState.SelectingFeature || state is InputState.SelectingDateMacro {
            return handleCandidateState(state: state, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // Big5 state
        if let big5State = state as? InputState.Big5 {
            return handleBig5State(state: big5State, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // Number state
        if let numberState = state as? InputState.Number {
            let result = handleNumberState(state: numberState, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
            if !result {
                if numberState.candidates.isEmpty {
                    return true
                }
                _ = handleCandidateState(state: numberState, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
            }
            return true
        }

        // ICU Transform state
        if let icuState = state as? InputState.IcuTransform {
            let result = handleIcuTransformState(state: icuState, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
            if !result {
                if icuState.candidates.isEmpty {
                    return true
                }
                _ = handleCandidateState(state: icuState, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
            }
            return true
        }

        guard let inputText = input.inputText, !inputText.isEmpty else {
            return false
        }

        let isFunctionKey = (input.isCommandHold || input.isOptionHold || input.isNumericPad) || input.isControlHotKey
        if !(state is InputState.NotEmpty) && !(state is InputState.AssociatedPhrasesPlain) && !((state as? InputState.AssociatedPhrases)?.autoTriggered == true) && isFunctionKey {
            return false
        }

        // Caps Lock processing
        if charCode == 8 || charCode == 13 || input.isAbsorbedArrowKey || input.isExtraChooseCandidateKey || input.isCursorForward || input.isCursorBackward {
            // Keep going
        } else if input.isCapsLockOn {
            clear()
            let empty = InputState.Empty()
            stateCallback(empty)
            if input.isShiftHold {
                return false
            }
            if charCode < 128 && isprint(Int32(charCode)) == 0 {
                return false
            }
            stateCallback(InputState.Committing(poppedText: inputText.lowercased()))
            stateCallback(empty)
            return true
        }

        if input.isNumericPad && !Preferences.selectCandidateWithNumericKeypad {
            if !input.isLeft && !input.isRight && !input.isDown && !input.isUp && charCode != 32 && isprint(Int32(charCode)) != 0 {
                clear()
                let empty = InputState.Empty()
                stateCallback(empty)
                stateCallback(InputState.Committing(poppedText: inputText.lowercased()))
                stateCallback(empty)
                return true
            }
        }

        // Associated phrases plain
        if let plainAssoc = state as? InputState.AssociatedPhrasesPlain {
            if handleCandidateState(state: plainAssoc, input: input, stateCallback: stateCallback, errorCallback: errorCallback) {
                return true
            }
            state = InputState.Empty()
            stateCallback(state)
        }

        // Associated phrases
        if let assoc = state as? InputState.AssociatedPhrases {
            if handleCandidateState(state: assoc, input: input, stateCallback: stateCallback, errorCallback: errorCallback) {
                return true
            }
            if assoc.autoTriggered {
                state = buildInputtingState()
                stateCallback(state)
            } else {
                return true
            }
        }

        // Candidate state
        if let choosing = state as? InputState.ChoosingCandidate {
            return handleCandidateState(state: choosing, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // Menu states
        if state is InputState.SelectingDictionary || state is InputState.ShowingCharInfo || state is InputState.CustomMenu {
            return handleCandidateState(state: state, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // Marking state
        if let marking = state as? InputState.Marking {
            if handleMarkingState(state: marking, input: input, stateCallback: stateCallback, errorCallback: errorCallback) {
                return true
            }
            state = marking.convertToInputting()
            stateCallback(state)
        }

        var keyConsumedByReading = false
        let skipBpmfHandling = input.isReservedKey || input.isControlHold

        let isValidKey = bpmfReadingBuffer.isValidKey(charCode: charCode)
        if !skipBpmfHandling && isValidKey {
            if bpmfReadingBuffer.hasToneMarkerOnly {
                bpmfReadingBuffer.clear()
            }
            let ch = Character(UnicodeScalar(charCode)!)
            bpmfReadingBuffer.combineKey(ch)
            keyConsumedByReading = true

            if !bpmfReadingBuffer.hasToneMarker {
                stateCallback(buildInputtingState())
                return true
            }
        }

        // Tone key modifying prior reading
        if bpmfReadingBuffer.hasToneMarkerOnly && grid.length > 0 && grid.cursor > 0 && Preferences.allowChangingPriorTone {
            let cursor = grid.cursor - 1
            let reading = grid.readings[cursor]
            if !reading.isEmpty && !reading.hasPrefix("_") {
                let tmpBuffer = BopomofoBuffer()
                let syllable = BopomofoSyllable.fromComposed(string: reading)
                let keys = BopomofoBuffer.keySequence(from: syllable)
                for k in keys {
                    tmpBuffer.combineKey(k)
                }
                if let charScalar = UnicodeScalar(charCode) {
                    tmpBuffer.combineKey(Character(charScalar))
                }
                let newReading = tmpBuffer.composedString
                if languageModel.hasUnigrams(reading: newReading) {
                    bpmfReadingBuffer.clear()
                    _ = grid.deleteReadingBeforeCursor()
                    _ = grid.insertReading(newReading)
                    walk()
                    stateCallback(buildInputtingState())
                    return true
                }
            }
        }

        var composeReading = isValidKey && bpmfReadingBuffer.hasToneMarker && !bpmfReadingBuffer.hasToneMarkerOnly
        composeReading = composeReading || (!bpmfReadingBuffer.isEmpty && (charCode == 32 || charCode == 13))

        if composeReading {
            let reading = bpmfReadingBuffer.composedString
            if !languageModel.hasUnigrams(reading: reading) {
                errorCallback()
                if Preferences.keepReadingUponCompositionError {
                    stateCallback(buildInputtingState())
                    return true
                }
                bpmfReadingBuffer.clear()
                if grid.length == 0 {
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                } else {
                    stateCallback(buildInputtingState())
                }
                return true
            }

            _ = grid.insertReading(reading)
            walk()

            if _inputMode != .plainBopomofo {
                let suggestion = LanguageModelManager.userOverrideModel.suggest(
                    currentWalk: latestWalk,
                    cursor: actualCandidateCursorIndex,
                    timestamp: Date().timeIntervalSince1970
                )
                if !suggestion.isEmpty {
                    let type: ReadingGrid.Node.OverrideType = suggestion.forceHighScoreOverride ? .overrideValueWithHighScore : .overrideValueWithScoreFromTopUnigram
                    grid.overrideCandidate(loc: actualCandidateCursorIndex, candidateValue: suggestion.candidate, overrideType: type)
                    walk()
                }
            }

            bpmfReadingBuffer.clear()
            let inputting = buildInputtingState() as! InputState.Inputting
            stateCallback(inputting)

            if _inputMode == .bopomofo && Preferences.associatedPhrasesEnabled {
                _ = handleAssociatedPhrase(with: inputting, useVerticalMode: input.useVerticalMode, stateCallback: stateCallback, errorCallback: errorCallback, autoTriggered: true, maxCandidateCount: 2)
            } else if _inputMode == .plainBopomofo {
                let choosing = buildCandidateState(from: inputting, useVerticalMode: input.useVerticalMode)
                if choosing.candidates.count == 1 {
                    clear()
                    let text = choosing.candidates[0].value
                    let candidateReading = choosing.candidates[0].reading
                    stateCallback(InputState.Committing(poppedText: text))

                    if !Preferences.associatedPhrasesEnabled {
                        stateCallback(InputState.Empty())
                    } else if let assoc = buildAssociatedPhrasePlainState(withReading: candidateReading, value: text, useVerticalMode: input.useVerticalMode) {
                        stateCallback(assoc)
                    } else {
                        stateCallback(InputState.Empty())
                    }
                } else {
                    stateCallback(choosing)
                }
            }
            return true
        }

        if keyConsumedByReading {
            stateCallback(buildInputtingState())
            return true
        }

        // Space and Down
        if bpmfReadingBuffer.isEmpty && state is InputState.NotEmpty && (input.isExtraChooseCandidateKey || charCode == 32 || (input.useVerticalMode && input.isVerticalModeOnlyChooseCandidateKey)) {
            if charCode == 32 {
                if input.isShiftHold || !Preferences.chooseCandidateUsingSpace {
                    if grid.cursor >= grid.length {
                        let composing = (state as! InputState.NotEmpty).composingBuffer
                        if !composing.isEmpty {
                            stateCallback(InputState.Committing(poppedText: composing))
                        }
                        clear()
                        stateCallback(InputState.Committing(poppedText: " "))
                        stateCallback(InputState.Empty())
                    } else if languageModel.hasUnigrams(reading: " ") {
                        _ = grid.insertReading(" ")
                        walk()
                        let inputting = buildInputtingState() as! InputState.Inputting
                        stateCallback(inputting)
                    }
                    return true
                }
            }

            let originalCursorIndex = grid.cursor
            if originalCursorIndex == grid.length && Preferences.selectPhraseAfterCursorAsCandidate && Preferences.moveCursorAfterSelectingCandidate {
                grid.setCursor(originalCursorIndex - 1)
            }
            let inputting = buildInputtingState() as! InputState.Inputting
            let choosingCandidates = buildCandidateState(from: inputting, useVerticalMode: input.useVerticalMode)
            choosingCandidates.originalCursorIndex = UInt(originalCursorIndex)
            stateCallback(choosingCandidates)
            return true
        }

        // Navigation keys
        if input.isCursorBackward || input.emacsKey == .backward {
            return handleBackward(state: state, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
        }
        if input.isCursorForward || input.emacsKey == .forward {
            return handleForward(state: state, input: input, stateCallback: stateCallback, errorCallback: errorCallback)
        }
        if input.isHome || input.emacsKey == .home {
            return handleHome(state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }
        if input.isEnd || input.emacsKey == .end {
            return handleEnd(state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }
        if input.isAbsorbedArrowKey {
            return handleAbsorbedArrowKey(state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }
        if charCode == 8 {
            return handleBackspace(state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }
        if input.isDelete || input.emacsKey == .delete {
            return handleDelete(state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // Esc
        if charCode == 27 {
            return handleEsc(state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // Tab
        if input.isTab {
            return handleTab(state: state, shiftIsHold: input.isShiftHold, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // Enter
        if charCode == 13 {
            if input.isControlHold {
                var string = ""
                switch Preferences.controlEnterOutput {
                case .off:
                    break
                case .bpmfReading:
                    string = currentBpmfReadingString()
                case .htmlRuby:
                    string = currentHtmlRuby()
                case .hanyuPinyin:
                    string = currentHanyuPinyin()
                case .brailleUnicode:
                    string = currentBraille(type: .unicode)
                case .brailleAscii:
                    string = currentBraille(type: .ascii)
                @unknown default:
                    break
                }
                if !string.isEmpty {
                    clear()
                    stateCallback(InputState.Committing(poppedText: string))
                    stateCallback(InputState.Empty())
                    return true
                }
            }
            return handleEnter(state: state, stateCallback: stateCallback, errorCallback: errorCallback)
        }

        // Enter Big5 code mode
        if input.isControlHold && (charCode == 96 || input.inputText == "`") {
            if Preferences.big5InputEnabled {
                clear()
                if let current = state as? InputState.Inputting {
                    let composing = current.composingBuffer
                    stateCallback(InputState.Committing(poppedText: composing))
                }
                let big5 = InputState.Big5(code: "")
                stateCallback(big5)
                return true
            }
        }

        // Enter feature selection mode
        if input.isControlHold && (input.keyCode == 42) {
            clear()
            if let current = state as? InputState.Inputting {
                let composing = current.composingBuffer
                stateCallback(InputState.Committing(poppedText: composing))
            }
            let selecting = InputState.SelectingFeature()
            stateCallback(selecting)
            return true
        }

        // Punctuation list
        if (charCode == 96 || input.inputText == "`") && !(input.isControlHold || input.isCommandHold || input.isOptionHold) {
            if languageModel.hasUnigrams(reading: "_punctuation_list") {
                if bpmfReadingBuffer.isEmpty {
                    _ = grid.insertReading("_punctuation_list")
                    walk()
                    let originalCursorIndex = grid.cursor
                    if Preferences.selectPhraseAfterCursorAsCandidate {
                        grid.setCursor(originalCursorIndex - 1)
                    }
                    let choosingCandidate = buildCandidateState(from: buildInputtingState() as! InputState.Inputting, useVerticalMode: input.useVerticalMode)
                    let choosingPunctuationList = InputState.ChoosingPunctuationList(choosingCandidate: choosingCandidate)
                    choosingPunctuationList.originalCursorIndex = UInt(originalCursorIndex)
                    stateCallback(choosingPunctuationList)
                } else {
                    errorCallback()
                }
                return true
            }
        }

        // Punctuation
        let punctuationNamePrefix = input.isControlHold ? "_ctrl_punctuation_" : (Preferences.halfWidthPunctuationEnabled ? "_half_punctuation_" : "_punctuation_")
        let layout = currentLayout()
        let charStr = (charCode > 0 && charCode < 128) ? String(Character(UnicodeScalar(charCode)!)) : (input.inputText ?? "")
        let customPunctuation = punctuationNamePrefix + layout + charStr
        if handlePunctuation(customPunctuation, state: state, useVerticalMode: input.useVerticalMode, stateCallback: stateCallback, errorCallback: errorCallback) {
            return true
        }

        let punctuation = punctuationNamePrefix + charStr
        if handlePunctuation(punctuation, state: state, useVerticalMode: input.useVerticalMode, stateCallback: stateCallback, errorCallback: errorCallback) {
            return true
        }

        if charCode >= 65 && charCode <= 90 { // 'A'...'Z'
            if Preferences.switchInputSourceUponShiftLetterKeyComboEnabled {
                clear()
                stateCallback(InputState.SwitchingInputSource(sourceID: Preferences.switchInputSourceUponShiftLetterKeyComboInputSourceID))
                return false
            }
            if Preferences.letterBehavior == 1 {
                let letter = "_letter_\(Character(UnicodeScalar(charCode)!))"
                if handlePunctuation(letter, state: state, useVerticalMode: input.useVerticalMode, stateCallback: stateCallback, errorCallback: errorCallback) {
                    return true
                }
            } else {
                if state is InputState.NotEmpty {
                    clear()
                    let empty = InputState.Empty()
                    stateCallback(empty)
                    state = empty
                }
            }
        }

        if state is InputState.NotEmpty || !bpmfReadingBuffer.isEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }

        return false
    }

    // MARK: - Navigation Implementation
    private func handleBackward(state: InputState, input: KeyHandlerInput, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard let current = state as? InputState.Inputting else { return false }
        if !bpmfReadingBuffer.isEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }

        if input.isShiftHold {
            if current.cursorIndex > 0 {
                if Preferences.bopomofoFontAnnotationSupportEnabled {
                    let updated = inputtingStateWithMarkingUnsupportedTooltip(current)
                    errorCallback()
                    stateCallback(updated)
                } else {
                    let prevPos = (current.composingBuffer as NSString).previousUtf16Position(for: Int(current.cursorIndex))
                    let marking = InputState.Marking(composingBuffer: current.composingBuffer, cursorIndex: current.cursorIndex, markerIndex: UInt(prevPos), readings: currentReadings)
                    marking.tooltipForInputting = current.tooltip
                    stateCallback(marking)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
        } else {
            if grid.cursor > 0 {
                grid.setCursor(grid.cursor - 1)
                stateCallback(buildInputtingState())
            } else {
                errorCallback()
                stateCallback(state)
            }
        }
        return true
    }

    private func handleForward(state: InputState, input: KeyHandlerInput, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard let current = state as? InputState.Inputting else { return false }
        if !bpmfReadingBuffer.isEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }

        if input.isShiftHold {
            if current.cursorIndex < current.composingBuffer.utf16.count {
                if Preferences.bopomofoFontAnnotationSupportEnabled {
                    let updated = inputtingStateWithMarkingUnsupportedTooltip(current)
                    errorCallback()
                    stateCallback(updated)
                } else {
                    let nextPos = (current.composingBuffer as NSString).nextUtf16Position(for: Int(current.cursorIndex))
                    let marking = InputState.Marking(composingBuffer: current.composingBuffer, cursorIndex: current.cursorIndex, markerIndex: UInt(nextPos), readings: currentReadings)
                    marking.tooltipForInputting = current.tooltip
                    stateCallback(marking)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
        } else {
            if grid.cursor < grid.length {
                grid.setCursor(grid.cursor + 1)
                stateCallback(buildInputtingState())
            } else {
                errorCallback()
                stateCallback(state)
            }
        }
        return true
    }

    private func handleHome(state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard state is InputState.Inputting else { return false }
        if !bpmfReadingBuffer.isEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }
        if grid.cursor > 0 {
            grid.setCursor(0)
            stateCallback(buildInputtingState())
        } else {
            errorCallback()
            stateCallback(state)
        }
        return true
    }

    private func handleEnd(state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard state is InputState.Inputting else { return false }
        if !bpmfReadingBuffer.isEmpty {
            errorCallback()
            stateCallback(state)
            return true
        }
        if grid.cursor != grid.length {
            grid.setCursor(grid.length)
            stateCallback(buildInputtingState())
        } else {
            errorCallback()
            stateCallback(state)
        }
        return true
    }

    private func handleAbsorbedArrowKey(state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard state is InputState.Inputting else { return false }
        if !bpmfReadingBuffer.isEmpty {
            errorCallback()
        }
        stateCallback(state)
        return true
    }

    private func handleBackspace(state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard state is InputState.Inputting else { return false }
        if bpmfReadingBuffer.hasToneMarkerOnly {
            bpmfReadingBuffer.clear()
        } else if bpmfReadingBuffer.isEmpty {
            if grid.cursor > 0 {
                _ = grid.deleteReadingBeforeCursor()
                walk()
            } else {
                errorCallback()
                stateCallback(state)
                return true
            }
        } else {
            bpmfReadingBuffer.backspace()
        }

        if bpmfReadingBuffer.isEmpty && grid.length == 0 {
            stateCallback(InputState.EmptyIgnoringPreviousState())
        } else {
            stateCallback(buildInputtingState())
        }
        return true
    }

    private func handleDelete(state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard state is InputState.Inputting else { return false }
        if bpmfReadingBuffer.isEmpty {
            if grid.cursor != grid.length {
                _ = grid.deleteReadingAfterCursor()
                walk()
                let inputting = buildInputtingState() as! InputState.Inputting
                if inputting.composingBuffer.isEmpty {
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                } else {
                    stateCallback(inputting)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
        } else {
            errorCallback()
            stateCallback(state)
        }
        return true
    }

    private func handleEsc(state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard state is InputState.Inputting else { return false }
        if Preferences.escToCleanInputBuffer {
            clear()
            stateCallback(InputState.EmptyIgnoringPreviousState())
        } else {
            if !bpmfReadingBuffer.isEmpty {
                bpmfReadingBuffer.clear()
                if grid.length == 0 {
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                } else {
                    stateCallback(buildInputtingState())
                }
            }
        }
        return true
    }

    private func handleTab(state: InputState, shiftIsHold: Bool, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard grid.length > 0 else { return false }
        guard let inputting = state as? InputState.Inputting, bpmfReadingBuffer.isEmpty else {
            errorCallback()
            return true
        }

        let candidateState = buildCandidateState(from: inputting, useVerticalMode: false)
        let candidates = candidateState.candidates
        if candidates.isEmpty {
            errorCallback()
            return true
        }

        var dummy: Int? = nil
        guard let nodeIdx = latestWalk.findNodeAt(cursor: actualCandidateCursorIndex, outCursorPastNode: &dummy) else {
            errorCallback()
            return true
        }
        let currentNode = latestWalk.nodes[nodeIdx]

        var currentIndex = 0
        if !currentNode.isOverridden {
            let first = candidates[0]
            if currentNode.reading == first.reading && currentNode.value == first.value {
                currentIndex = shiftIsHold ? candidates.count - 1 : 1
            }
        } else {
            for (idx, candidate) in candidates.enumerated() {
                if currentNode.reading == candidate.reading && currentNode.value == candidate.value {
                    if shiftIsHold {
                        currentIndex = (idx == 0) ? candidates.count - 1 : idx - 1
                    } else {
                        currentIndex = idx + 1
                    }
                    break
                }
            }
        }

        if currentIndex >= candidates.count {
            currentIndex = 0
        }

        let chosen = candidates[currentIndex]
        let originalCursor = grid.cursor
        fixNode(reading: chosen.reading, value: chosen.value, originalCursorIndex: originalCursor, useMoveCursorAfterSelectionSetting: false)
        stateCallback(buildInputtingState())
        return true
    }

    private func handleEnter(state: InputState, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard let current = state as? InputState.Inputting else { return false }
        clear()
        stateCallback(InputState.Committing(poppedText: current.composingBuffer))
        stateCallback(InputState.Empty())
        return true
    }

    private func handlePunctuation(_ customPunctuation: String, state: InputState, useVerticalMode: Bool, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        guard languageModel.hasUnigrams(reading: customPunctuation) else { return false }

        if Preferences.repeatedPunctuationToSelectCandidateEnabled {
            let prefixCursorIndex = grid.cursor
            let actualPrefixCursor = prefixCursorIndex > 0 ? prefixCursorIndex - 1 : 0
            var dummy: Int? = nil
            if let nodeIdx = latestWalk.findNodeAt(cursor: actualPrefixCursor, outCursorPastNode: &dummy) {
                let currentNode = latestWalk.nodes[nodeIdx]
                if currentNode.reading == customPunctuation {
                    let candidates = grid.candidatesAt(loc: actualPrefixCursor)
                    if candidates.count > 1 {
                        if Preferences.selectPhraseAfterCursorAsCandidate {
                            grid.setCursor(actualPrefixCursor)
                        }
                        _ = handleTab(state: state, shiftIsHold: false, stateCallback: stateCallback, errorCallback: errorCallback)
                        grid.setCursor(prefixCursorIndex)
                        stateCallback(buildInputtingState())
                        return true
                    }
                }
            }
        }

        if bpmfReadingBuffer.isEmpty {
            _ = grid.insertReading(customPunctuation)
            walk()
        } else {
            errorCallback()
            stateCallback(state)
            return true
        }

        let inputting = buildInputtingState() as! InputState.Inputting
        stateCallback(inputting)

        if _inputMode == .bopomofo && Preferences.associatedPhrasesEnabled {
            _ = handleAssociatedPhrase(with: inputting, useVerticalMode: useVerticalMode, stateCallback: stateCallback, errorCallback: errorCallback, autoTriggered: true, maxCandidateCount: 0)
        } else if _inputMode == .plainBopomofo && bpmfReadingBuffer.isEmpty {
            let choosing = buildCandidateState(from: inputting, useVerticalMode: useVerticalMode)
            if choosing.candidates.count == 1 {
                clear()
                stateCallback(InputState.Committing(poppedText: choosing.candidates[0].value))
                stateCallback(InputState.Empty())
            } else {
                stateCallback(choosing)
            }
        }
        return true
    }

    // MARK: - Candidate State Handler
    private func handleCandidateState(state: InputState, input: KeyHandlerInput, stateCallback: @escaping (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        let inputText = input.inputText
        let charCode = Int(input.charCode)
        let controller = delegate?.candidateController(for: self) as? CandidateController

        if let assoc = state as? InputState.AssociatedPhrases, assoc.autoTriggered {
            if input.isTab {
                let expanded = assoc.toggle(autoTriggered: false)
                stateCallback(expanded)
                return true
            }
            if input.isShiftHold && (charCode == 13 || input.isEnter) {
                if let controller = controller {
                    delegate?.keyHandler(self, didSelectCandidateAt: Int(controller.selectedCandidateIndex), candidateController: controller)
                }
                return true
            }
            return false
        }

        if state is InputState.ChoosingPunctuationList {
            if input.inputText == "`" {
                if Preferences.selectPhraseAfterCursorAsCandidate {
                    _ = grid.deleteReadingAfterCursor()
                } else {
                    _ = grid.deleteReadingBeforeCursor()
                }
                walk()
                if grid.length > 0 {
                    handleForceCommit(stateCallback: stateCallback)
                } else {
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                }
                stateCallback(InputState.SelectingFeature())
                return true
            }

            let key = "_punctuation_list_" + (input.inputText ?? "")
            if languageModel.hasUnigrams(reading: key) {
                if Preferences.selectPhraseAfterCursorAsCandidate {
                    _ = grid.deleteReadingAfterCursor()
                } else {
                    _ = grid.deleteReadingBeforeCursor()
                }
                _ = grid.insertReading(key)
                walk()
                if _inputMode == .plainBopomofo {
                    let choosing = buildCandidateState(from: buildInputtingState() as! InputState.Inputting, useVerticalMode: input.useVerticalMode)
                    if choosing.candidates.count == 1 {
                        clear()
                        stateCallback(InputState.Committing(poppedText: choosing.candidates[0].value))
                        stateCallback(InputState.Empty())
                    } else {
                        stateCallback(choosing)
                    }
                } else {
                    stateCallback(buildInputtingState())
                }
                return true
            }
        }

        var cancelCandidateKey = (charCode == 27) || (charCode == 8) || input.isDelete

        var isCursorMovingLeft = false
        var isCursorMovingRight = false

        if state is InputState.ChoosingPunctuationList {
            isCursorMovingLeft = false
            isCursorMovingRight = false
        } else if input.isShiftHold {
            isCursorMovingLeft = input.isLeft
            isCursorMovingRight = input.isRight
        } else {
            switch Preferences.allowMovingCursorWhenChoosingCandidates {
            case .disabled:
                break
            case .useJK:
                isCursorMovingLeft = (input.inputText == "j")
                isCursorMovingRight = (input.inputText == "k")
            case .useHL:
                isCursorMovingLeft = (input.inputText == "h")
                isCursorMovingRight = (input.inputText == "l")
            @unknown default:
                break
            }
        }

        if let choosing = state as? InputState.ChoosingCandidate, (isCursorMovingLeft || isCursorMovingRight) {
            if isCursorMovingLeft {
                if grid.cursor > 0 {
                    grid.setCursor(grid.cursor - 1)
                } else {
                    errorCallback()
                    return true
                }
            } else if isCursorMovingRight {
                if grid.cursor < grid.length {
                    grid.setCursor(grid.cursor + 1)
                } else {
                    errorCallback()
                    return true
                }
            }
            let newState = buildCandidateState(from: buildInputtingState() as! InputState.Inputting, useVerticalMode: choosing.useVerticalMode)
            stateCallback(newState)
            return true
        }

        let invalidPrefixes = ["_half_punctuation_", "_ctrl_punctuation_", "_letter_", "_number_", "_punctuation_"]

        if _inputMode == .bopomofo, let currentState = state as? InputState.ChoosingCandidate {
            let isPlusKey = (input.inputText == "=" || input.inputText == "+")
            let isMinusKey = (input.inputText == "-" || input.inputText == "_")
            if isPlusKey || isMinusKey {
                let index = Int(controller?.selectedCandidateIndex ?? 0)
                guard index >= 0 && index < currentState.candidates.count else { return true }
                let candidate = currentState.candidates[index]
                let reading = candidate.reading

                if candidate.value != candidate.rawValue {
                    return true
                }
                for pfx in invalidPrefixes {
                    if reading.hasPrefix(pfx) {
                        errorCallback()
                        return true
                    }
                }
                if !reading.contains("-") {
                    errorCallback()
                    return true
                }

                var entries: [InputState.CustomMenuEntry] = []
                var title = ""

                if isPlusKey {
                    let boost = InputState.CustomMenuEntry(title: NSLocalizedString("Boost", comment: "")) { [weak self] in
                        guard let self = self else { return }
                        _ = self.delegate?.keyHandler(self, didRequestBoostScoreForPhrase: candidate.value, reading: reading)
                        _ = self.delegate?.keyHandlerDidRequestReloadLanguageModel(self)
                        self.walk()
                        stateCallback(self.buildInputtingState())
                    }
                    entries.append(boost)
                    title = String(format: NSLocalizedString("Do you want to boost the score of the phrase \"%@\"?", comment: ""), candidate.value)
                } else if isMinusKey {
                    let exclude = InputState.CustomMenuEntry(title: NSLocalizedString("Exclude", comment: "")) { [weak self] in
                        guard let self = self else { return }
                        _ = self.delegate?.keyHandler(self, didRequestExcludePhrase: candidate.value, reading: reading)
                        _ = self.delegate?.keyHandlerDidRequestReloadLanguageModel(self)
                        self.walk()
                        stateCallback(self.buildInputtingState())
                    }
                    entries.append(exclude)
                    title = String(format: NSLocalizedString("Do you want to exclude the phrase \"%@\"?", comment: ""), candidate.value)
                }

                let cancel = InputState.CustomMenuEntry(title: NSLocalizedString("Cancel", comment: "")) {
                    stateCallback(currentState)
                    controller?.selectedCandidateIndex = UInt(index)
                }
                entries.append(cancel)

                let confirm = InputState.CustomMenu(
                    composingBuffer: currentState.composingBuffer,
                    cursorIndex: currentState.cursorIndex,
                    title: title,
                    entries: entries,
                    previousState: currentState,
                    selectedIndex: index
                )
                stateCallback(confirm)
                return true
            }
        }

        // Question mark
        if _inputMode == .bopomofo && input.inputText == "?" {
            if state is InputState.ShowingCharInfo || state is InputState.SelectingDictionary {
                cancelCandidateKey = true
            } else if let currentState = state as? InputState.ChoosingCandidate {
                let index = Int(controller?.selectedCandidateIndex ?? 0)
                guard index >= 0 && index < currentState.candidates.count else { return true }
                let candidate = currentState.candidates[index]
                let reading = candidate.reading
                for pfx in invalidPrefixes {
                    if reading.hasPrefix(pfx) {
                        errorCallback()
                        return true
                    }
                }
                let newState = InputState.SelectingDictionary(previousState: currentState, selectedString: candidate.displayText, selectedIndex: index)
                stateCallback(newState)
                return true
            } else if let assoc = state as? InputState.AssociatedPhrases, assoc.autoTriggered {
                return false
            }
        }

        if cancelCandidateKey {
            if let current = state as? InputState.ShowingCharInfo {
                let selIdx = current.previousState.selectedIndex
                stateCallback(current.previousState.previousState)
                if let ctrl = delegate?.candidateController(for: self) as? CandidateController {
                    ctrl.selectedCandidateIndex = UInt(selIdx)
                }
            } else if let current = state as? InputState.SelectingDictionary {
                let selIdx = current.selectedIndex
                stateCallback(current.previousState)
                if let ctrl = delegate?.candidateController(for: self) as? CandidateController {
                    ctrl.selectedCandidateIndex = UInt(selIdx)
                }
            } else if let current = state as? InputState.CustomMenu {
                let selIdx = current.selectedIndex
                stateCallback(current.previousState)
                if let ctrl = delegate?.candidateController(for: self) as? CandidateController {
                    ctrl.selectedCandidateIndex = UInt(selIdx)
                }
            } else if state is InputState.SelectingFeature {
                clear()
                stateCallback(InputState.EmptyIgnoringPreviousState())
            } else if let current = state as? InputState.AssociatedPhrases {
                if current.autoTriggered {
                    return false
                }
                let selIdx = current.selectedIndex
                stateCallback(current.previousState)
                if let ctrl = delegate?.candidateController(for: self) as? CandidateController {
                    ctrl.selectedCandidateIndex = UInt(selIdx)
                }
            } else if state is InputState.ChoosingPunctuationList {
                if Preferences.selectPhraseAfterCursorAsCandidate {
                    _ = grid.deleteReadingAfterCursor()
                } else {
                    _ = grid.deleteReadingBeforeCursor()
                }
                if grid.length == 0 {
                    clear()
                    stateCallback(InputState.EmptyIgnoringPreviousState())
                } else {
                    walk()
                    stateCallback(buildInputtingState())
                }
            } else if state is InputState.AssociatedPhrasesPlain || _inputMode == .plainBopomofo {
                clear()
                stateCallback(InputState.EmptyIgnoringPreviousState())
            } else if let current = state as? InputState.ChoosingCandidate {
                grid.setCursor(Int(current.originalCursorIndex))
                stateCallback(buildInputtingState())
            } else {
                stateCallback(buildInputtingState())
            }
            return true
        }

        // Enter in candidate state
        if charCode == 13 || input.isEnter {
            if let numberState = state as? InputState.Number {
                guard !numberState.candidates.isEmpty else { return true }
                let selIdx = Int(controller?.selectedCandidateIndex ?? 0)
                let idx = (selIdx >= 0 && selIdx < numberState.candidates.count) ? selIdx : 0
                let candidate = numberState.candidates[idx]
                stateCallback(InputState.Committing(poppedText: candidate))
                stateCallback(InputState.Empty())
                return true
            }

            if let icuState = state as? InputState.IcuTransform {
                guard !icuState.candidates.isEmpty else { return true }
                let selIdx = Int(controller?.selectedCandidateIndex ?? 0)
                let idx = (selIdx >= 0 && selIdx < icuState.candidates.count) ? selIdx : 0
                let candidate = icuState.candidates[idx]
                stateCallback(InputState.Committing(poppedText: candidate))
                stateCallback(InputState.Empty())
                return true
            }

            if Preferences.shiftEnterEnabled && _inputMode == .bopomofo && input.isShiftHold,
               let current = state as? InputState.ChoosingCandidate {
                let selIdx = Int(controller?.selectedCandidateIndex ?? 0)
                guard selIdx >= 0 && selIdx < current.candidates.count else { return true }
                let candidate = current.candidates[selIdx]

                let params = BuildAssociatedPhraseParams()
                params.previousState = current
                params.prefixCursorIndex = computeActualCursorIndex(Int(current.originalCursorIndex))
                params.reading = candidate.reading
                params.value = candidate.value
                params.candidateIndex = 0
                params.useVerticalMode = current.useVerticalMode
                params.autoTriggered = false
                if let newState = buildAssociatedPhraseState(with: params) {
                    stateCallback(newState)
                } else {
                    errorCallback()
                }
                return true
            }

            if state is InputState.AssociatedPhrasesPlain {
                clear()
                stateCallback(InputState.EmptyIgnoringPreviousState())
                return true
            }

            if let controller = controller {
                delegate?.keyHandler(self, didSelectCandidateAt: Int(controller.selectedCandidateIndex), candidateController: controller)
            }
            return true
        }

        if charCode == 32 && (state as? InputState.AssociatedPhrases)?.autoTriggered == true {
            return false
        }

        var isPageDown = (charCode == 32 || input.isPageDown || input.emacsKey == .nextPage)
        var isPageUp = input.isPageUp
        switch Preferences.allowMovingCursorWhenChoosingCandidates {
        case .useJK:
            isPageDown = isPageDown || (input.inputText == "l")
            isPageUp = isPageUp || (input.inputText == "h")
        case .useHL:
            isPageDown = isPageDown || (input.inputText == "k")
            isPageUp = isPageUp || (input.inputText == "j")
        case .disabled:
            break
        @unknown default:
            break
        }

        if isPageDown {
            if (state as? InputState.AssociatedPhrases)?.autoTriggered == true {
                return false
            }
            if let controller = controller {
                if !controller.showNextPage() {
                    errorCallback()
                }
            }
            return true
        }

        if isPageUp {
            if (state as? InputState.AssociatedPhrases)?.autoTriggered == true {
                return false
            }
            if let controller = controller {
                if !controller.showPreviousPage() {
                    errorCallback()
                }
            }
            return true
        }

        let candidateCount = (state as? CandidateProvider)?.candidateCount ?? 0

        if input.isTab {
            if let gridCtrl = controller as? GridCandidateController {
                gridCtrl.toggleExpand()
                return true
            }
        }

        if input.isLeft {
            if let assoc = state as? InputState.AssociatedPhrases, assoc.autoTriggered {
                if let controller = controller {
                    if controller is HorizontalCandidateController && controller.selectedCandidateIndex == 0 {
                        return false
                    }
                    if !(controller is HorizontalCandidateController) {
                        return false
                    }
                }
                if input.isShiftHold {
                    return false
                }
            }

            if let horiz = controller as? HorizontalCandidateController {
                if !horiz.highlightPreviousCandidate() { errorCallback() }
            } else if let gridCtrl = controller as? GridCandidateController {
                if !gridCtrl.highlightCandidateLeft() { errorCallback() }
            } else if let controller = controller {
                if !controller.showPreviousPage() { errorCallback() }
            }
            return true
        }

        if input.emacsKey == .backward {
            if let controller = controller {
                if !controller.highlightPreviousCandidate() { errorCallback() }
            }
            return true
        }

        if input.isRight {
            if let assoc = state as? InputState.AssociatedPhrases, assoc.autoTriggered {
                if let controller = controller {
                    if controller is HorizontalCandidateController && controller.selectedCandidateIndex == candidateCount - 1 {
                        return false
                    }
                    if !(controller is HorizontalCandidateController) {
                        return false
                    }
                }
                if input.isShiftHold {
                    return false
                }
            }

            if let horiz = controller as? HorizontalCandidateController {
                if !horiz.highlightNextCandidate() { errorCallback() }
            } else if let gridCtrl = controller as? GridCandidateController {
                if !gridCtrl.highlightCandidateRight() { errorCallback() }
            } else if let controller = controller {
                if !controller.showNextPage() { errorCallback() }
            }
            return true
        }

        if input.emacsKey == .forward {
            if let controller = controller {
                if !controller.highlightNextCandidate() { errorCallback() }
            }
            return true
        }

        if input.isUp {
            if let controller = controller as? HorizontalCandidateController {
                if !controller.showPreviousPage() { errorCallback() }
            } else if let gridCtrl = controller as? GridCandidateController {
                if !gridCtrl.highlightCandidateUp() { errorCallback() }
            } else if let controller = controller {
                if !controller.highlightPreviousCandidate() { errorCallback() }
            }
            return true
        }

        if input.isDown {
            if let controller = controller as? HorizontalCandidateController {
                if !controller.showNextPage() { errorCallback() }
            } else if let gridCtrl = controller as? GridCandidateController {
                if !gridCtrl.highlightCandidateDown() { errorCallback() }
            } else if let controller = controller {
                if !controller.highlightNextCandidate() { errorCallback() }
            }
            return true
        }

        if input.isHome || input.emacsKey == .home {
            if let controller = controller {
                if controller.selectedCandidateIndex == 0 {
                    errorCallback()
                } else {
                    controller.selectedCandidateIndex = 0
                }
            }
            return true
        }

        if candidateCount == 0 {
            return false
        }

        if (input.isEnd || input.emacsKey == .end) && candidateCount > 0 {
            if let controller = controller {
                if controller.selectedCandidateIndex == candidateCount - 1 {
                    errorCallback()
                } else {
                    controller.selectedCandidateIndex = UInt(candidateCount - 1)
                }
            }
            return true
        }

        var useInputTextIgnoringModifiers = false
        if state is InputState.AssociatedPhrasesPlain || state is InputState.Number || state is InputState.IcuTransform {
            useInputTextIgnoringModifiers = true
        } else if let assoc = state as? InputState.AssociatedPhrases {
            useInputTextIgnoringModifiers = assoc.autoTriggered
        }

        if useInputTextIgnoringModifiers && !input.isShiftHold {
            return false
        }

        let rawMatch = useInputTextIgnoringModifiers ? input.inputTextIgnoringModifiers : inputText
        guard let match = rawMatch else { return false }
        var foundIndex: Int? = nil

        if let controller = controller {
            for (j, label) in controller.keyLabels.enumerated() {
                if match.compare(label.key, options: .caseInsensitive) == .orderedSame {
                    foundIndex = j
                    break
                }
            }

            if let j = foundIndex {
                let candidateIdx = controller.candidateIndexAtKeyLabelIndex(UInt(j))
                if candidateIdx != UInt.max {
                    delegate?.keyHandler(self, didSelectCandidateAt: Int(candidateIdx), candidateController: controller)
                    return true
                }
            }
        }

        if useInputTextIgnoringModifiers {
            return false
        }

        if _inputMode == .plainBopomofo {
            let layout = currentLayout()
            let pfx = input.isControlHold ? "_ctrl_punctuation_" : (Preferences.halfWidthPunctuationEnabled ? "_half_punctuation_" : "_punctuation_")
            let customPunctuation = pfx + layout + String(Character(UnicodeScalar(charCode) ?? " "))
            let punctuation = pfx + String(Character(UnicodeScalar(charCode) ?? " "))

            var shouldAutoSelect = bpmfReadingBuffer.isValidKey(charCode: charCode) || languageModel.hasUnigrams(reading: customPunctuation) || languageModel.hasUnigrams(reading: punctuation)

            if !shouldAutoSelect && charCode >= 65 && charCode <= 90 {
                let letter = "_letter_\(Character(UnicodeScalar(charCode)!))"
                if languageModel.hasUnigrams(reading: letter) {
                    shouldAutoSelect = true
                }
            }

            if shouldAutoSelect {
                let candidateIdx: UInt
                if let controller = controller {
                    candidateIdx = controller.candidateIndexAtKeyLabelIndex(0)
                } else {
                    candidateIdx = 0
                }
                if candidateIdx != UInt.max {
                    if let controller = controller {
                        delegate?.keyHandler(self, didSelectCandidateAt: Int(candidateIdx), candidateController: controller)
                    }
                    clear()
                    let empty = InputState.EmptyIgnoringPreviousState()
                    stateCallback(empty)
                    _ = handle(input: input, state: empty, stateCallback: stateCallback, errorCallback: errorCallback)
                }
                return true
            }
        }

        errorCallback()
        return true
    }

    // MARK: - Marking State Handler
    private func handleMarkingState(state: InputState.Marking, input: KeyHandlerInput, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        let charCode = Int(input.charCode)
        if charCode == 27 {
            stateCallback(buildInputtingState())
            return true
        }

        if charCode == 13 {
            if delegate?.keyHandler(self, didRequestWriteUserPhraseWith: state) != true {
                errorCallback()
                return true
            }
            stateCallback(buildInputtingState())
            return true
        }

        if input.inputText == "?" && state.markedRange.length > 0 {
            let newState = InputState.SelectingDictionary(previousState: state, selectedString: state.selectedText, selectedIndex: 0)
            stateCallback(newState)
            return true
        }

        if (input.isCursorBackward || input.emacsKey == .backward) && input.isShiftHold {
            var index = state.markerIndex
            if index > 0 {
                let prev = (state.composingBuffer as NSString).previousUtf16Position(for: Int(index))
                index = UInt(prev)
                let marking = InputState.Marking(composingBuffer: state.composingBuffer, cursorIndex: state.cursorIndex, markerIndex: index, readings: state.readings)
                marking.tooltipForInputting = state.tooltipForInputting
                if marking.markedRange.length == 0 {
                    stateCallback(marking.convertToInputting())
                } else {
                    stateCallback(marking)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
            return true
        }

        if (input.isCursorForward || input.emacsKey == .forward) && input.isShiftHold {
            var index = state.markerIndex
            if index < state.composingBuffer.utf16.count {
                let next = (state.composingBuffer as NSString).nextUtf16Position(for: Int(index))
                index = UInt(next)
                let marking = InputState.Marking(composingBuffer: state.composingBuffer, cursorIndex: state.cursorIndex, markerIndex: index, readings: state.readings)
                marking.tooltipForInputting = state.tooltipForInputting
                if marking.markedRange.length == 0 {
                    stateCallback(marking.convertToInputting())
                } else {
                    stateCallback(marking)
                }
            } else {
                errorCallback()
                stateCallback(state)
            }
            return true
        }

        return false
    }

    // MARK: - Specialized Number & ICU Handlers
    private func candidatesForNumberString(_ number: String) -> [String] {
        guard !number.isEmpty else { return [] }
        var array: [String] = []
        array.append(contentsOf: NumberInputHelper.candidateFor(numberString: number))

        let key = "_number_\(number)"
        if languageModel.hasUnigrams(reading: key) {
            let unigrams = languageModel.getUnigrams(reading: key)
            for u in unigrams {
                if !array.contains(u.value) {
                    array.append(u.value)
                }
            }
        }

        let comps = NumberInputHelper.split(numberString: number)
        let intPart = comps[0]
        let decPart = comps[1]
        let suzhou = SuzhouNumbers.generate(intPart: intPart, decPart: decPart, unit: "[單位]", preferInitialVertical: true)
        array.append(suzhou)
        return array
    }

    private func candidatesForIcuTransformString(_ string: String) -> [String] {
        guard !string.isEmpty else { return [] }
        let transforms: [StringTransform] = [
            .latinToHiragana,
            .latinToKatakana,
            .latinToHangul,
            .latinToThai,
            .latinToGreek,
            StringTransform("Latin-Cyrillic"),
            .latinToArabic,
            .latinToHebrew,
            StringTransform("Latin-Devanagari")
        ]

        var array: [String] = []
        for t in transforms {
            if let transformed = string.applyingTransform(t, reverse: false), transformed != string, !array.contains(transformed) {
                array.append(transformed)
            }
        }
        return array
    }

    private func handleNumberState(state: InputState.Number, input: KeyHandlerInput, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        let charCode = Int(input.charCode)
        if charCode == 27 {
            stateCallback(InputState.Empty())
            return true
        }

        if charCode == 8 || input.isDelete {
            var number = state.number
            if !number.isEmpty {
                number.removeLast()
            } else {
                errorCallback()
                return true
            }
            let candidates = candidatesForNumberString(number)
            stateCallback(InputState.Number(number: number, candidates: candidates))
            return true
        }

        if charCode >= 48 && charCode <= 57 { // '0'...'9'
            if state.number.count > 20 {
                errorCallback()
                return true
            }
            let appended = state.number + String(Character(UnicodeScalar(charCode)!))
            let candidates = candidatesForNumberString(appended)
            stateCallback(InputState.Number(number: appended, candidates: candidates))
            return true
        } else if charCode == 46 { // '.'
            if state.number.contains(".") || state.number.isEmpty || state.number.count > 20 {
                errorCallback()
                return true
            }
            let appended = state.number + "."
            let candidates = candidatesForNumberString(appended)
            stateCallback(InputState.Number(number: appended, candidates: candidates))
            return true
        }

        return false
    }

    private func handleIcuTransformState(state: InputState.IcuTransform, input: KeyHandlerInput, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        let charCode = Int(input.charCode)
        if charCode == 27 {
            stateCallback(InputState.Empty())
            return true
        }

        if charCode == 8 || input.isDelete {
            var str = state.string
            if !str.isEmpty {
                str.removeLast()
            } else {
                errorCallback()
                return true
            }
            let candidates = candidatesForIcuTransformString(str)
            stateCallback(InputState.IcuTransform(string: str, candidates: candidates))
            return true
        }

        if input.isShiftHold, let controller = delegate?.candidateController(for: self) as? CandidateController {
            if let match = input.inputTextIgnoringModifiers {
                for label in controller.keyLabels {
                    if match.compare(label.key, options: .caseInsensitive) == .orderedSame {
                        return false
                    }
                }
            }
        }

        if charCode < 128 && isprint(Int32(charCode)) != 0 {
            if state.string.count > 100 {
                errorCallback()
                return true
            }
            let appended = state.string + String(Character(UnicodeScalar(charCode)!))
            let candidates = candidatesForIcuTransformString(appended)
            stateCallback(InputState.IcuTransform(string: appended, candidates: candidates))
            return true
        }

        return false
    }

    private func decodeBig5(val: UInt16) -> String? {
        let high = UInt8(val >> 8)
        let low = UInt8(val & 0xFF)
        let bytes = [high, low]
        let encodings: [CFStringEncoding] = [
            CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue),
            CFStringEncoding(CFStringEncodings.big5.rawValue),
            CFStringEncoding(CFStringEncodings.big5_E.rawValue),
            CFStringEncoding(CFStringEncodings.dosChineseTrad.rawValue)
        ]
        for enc in encodings {
            if let cfString = CFStringCreateWithBytes(kCFAllocatorDefault, bytes, bytes.count, enc, false) {
                return cfString as String
            }
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(enc)
            if let str = String(data: Data(bytes), encoding: String.Encoding(rawValue: nsEnc)) {
                return str
            }
        }
        var nullTerminated: [CChar] = [CChar(bitPattern: high), CChar(bitPattern: low), 0]
        for enc in encodings {
            if let cfString = CFStringCreateWithCString(kCFAllocatorDefault, &nullTerminated, enc) {
                return cfString as String
            }
        }
        return nil
    }

    private func handleBig5State(state: InputState.Big5, input: KeyHandlerInput, stateCallback: (InputState) -> Void, errorCallback: () -> Void) -> Bool {
        var charCode = Int(input.charCode)
        if charCode == 0, let text = input.inputText, let first = text.utf16.first {
            charCode = Int(first)
        }

        if charCode == 27 {
            stateCallback(InputState.Empty())
            return true
        }

        if charCode == 8 || input.isDelete {
            var code = state.code
            if !code.isEmpty {
                code.removeLast()
            }
            stateCallback(InputState.Big5(code: code))
            return true
        }

        if (charCode >= 48 && charCode <= 57) || (charCode >= 65 && charCode <= 70) || (charCode >= 97 && charCode <= 102) {
            guard let scalar = UnicodeScalar(charCode) else {
                errorCallback()
                return true
            }
            let ch = Character(scalar).uppercased()
            let appended = state.code + ch
            if appended.count == 4 {
                guard let val = UInt16(appended, radix: 16) else {
                    errorCallback()
                    stateCallback(InputState.Empty())
                    return true
                }
                if let str = decodeBig5(val: val) {
                    stateCallback(InputState.Committing(poppedText: str))
                    stateCallback(InputState.Empty())
                } else {
                    errorCallback()
                    stateCallback(InputState.Empty())
                }
            } else {
                stateCallback(InputState.Big5(code: appended))
            }
            return true
        }

        errorCallback()
        return true
    }
}
