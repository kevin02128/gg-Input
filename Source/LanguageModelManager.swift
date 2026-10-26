import Foundation
import SwiftEngine
import OpenCCBridge

@objc(LanguageModelManager)
final class LanguageModelManager: NSObject {
    static let engineMcBopomofo = EngineLM()
    static let enginePlainBopomofo = EngineLM()
    static let userOverrideModel = UserOverrideModel(capacity: 500, decayConstant: 5400.0)

    private static let kUserDataTemplateName = "template-data"
    private static let kUserDataPlainBopomofoTemplateName = "template-data-plain-bpmf"
    private static let kExcludedPhrasesMcBopomofoTemplateName = "template-exclude-phrases"
    private static let kExcludedPhrasesPlainBopomofoTemplateName = "template-exclude-phrases-plain-bpmf"
    private static let kPhraseReplacementTemplateName = "template-phrases-replacement"
    private static let kTemplateExtension = "txt"

    private static func findDataFile(named name: String) -> String? {
        let cls: AnyClass? = NSClassFromString("McBopomofoInputMethodController") ?? NSClassFromString("gg.McBopomofoInputMethodController")
        if let cls = cls, let path = Bundle(for: cls).path(forResource: name, ofType: "txt") {
            return path
        }
        if let path = Bundle.main.path(forResource: name, ofType: "txt") {
            return path
        }
        for bundle in Bundle.allBundles {
            if let path = bundle.path(forResource: name, ofType: "txt") {
                return path
            }
        }
        return nil
    }

    @objc static func loadDataModels() {
        loadDataModel(.bopomofo)
        loadDataModel(.plainBopomofo)
    }

    static func loadDataModel(_ mode: InputMode) {
        if mode == .bopomofo {
            if !engineMcBopomofo.isDataModelLoaded {
                if let path = findDataFile(named: "data") {
                    _ = engineMcBopomofo.loadLanguageModel(path: path)
                }
            }
            if !engineMcBopomofo.isAssociatedPhrasesLoaded {
                if let path = findDataFile(named: "associated-phrases-v2") {
                    _ = engineMcBopomofo.loadAssociatedPhrases(path: path)
                }
            }
            if !engineMcBopomofo.isVariantAnnotatorLoaded {
                if let puaPath = findDataFile(named: "bpmfvs-pua"),
                   let varPath = findDataFile(named: "bpmfvs-variants") {
                    _ = engineMcBopomofo.loadVariantAnnotator(puaPath: puaPath, variantsPath: varPath)
                }
            }
        }

        if mode == .plainBopomofo {
            if !enginePlainBopomofo.isDataModelLoaded {
                if let path = findDataFile(named: "data-plain-bpmf") {
                    _ = enginePlainBopomofo.loadLanguageModel(path: path)
                }
            }
            if !enginePlainBopomofo.isAssociatedPhrasesLoaded {
                if let path = findDataFile(named: "associated-phrases-v2") {
                    _ = enginePlainBopomofo.loadAssociatedPhrases(path: path)
                }
            }
            if !enginePlainBopomofo.isVariantAnnotatorLoaded {
                if let puaPath = findDataFile(named: "bpmfvs-pua"),
                   let varPath = findDataFile(named: "bpmfvs-variants") {
                    _ = enginePlainBopomofo.loadVariantAnnotator(puaPath: puaPath, variantsPath: varPath)
                }
            }
        }
    }

    @objc(loadUserPhrasesWithPlainBopomofoEnabled:)
    static func loadUserPhrases(enableForPlainBopomofo: Bool) {
        engineMcBopomofo.loadUserPhrases(
            userPhrasesPath: userPhrasesDataPathMcBopomofo,
            excludedPhrasesPath: excludedPhrasesDataPathMcBopomofo
        )
        enginePlainBopomofo.loadUserPhrases(
            userPhrasesPath: enableForPlainBopomofo ? userPhrasesDataPathPlainBopomofo : nil,
            excludedPhrasesPath: excludedPhrasesDataPathPlainBopomofo
        )
    }

    @objc static func loadUserPhraseReplacement() {
        engineMcBopomofo.loadPhraseReplacementMap(path: phraseReplacementDataPathMcBopomofo)
    }

    @objc static func setupDataModelValueConverter() {
        let macroConverter: (String) -> String = { input in
            InputMacroController.shared.handle(input)
        }

        let converter: (String) -> String = { input in
            guard Preferences.chineseConversionEnabled, Preferences.chineseConversionStyle == .model else {
                return input
            }
            return OpenCCBridge.shared.convertToSimplified(input) ?? input
        }

        engineMcBopomofo.macroConverter = macroConverter
        engineMcBopomofo.externalConverter = converter
        enginePlainBopomofo.externalConverter = converter
    }

    @objc static var dataFolderPath: String {
        let useCustomLocation = Preferences.useCustomUserPhraseLocation
        if !useCustomLocation {
            return UserPhraseLocationHelper.defaultUserPhraseLocation
        }
        return Preferences.customUserPhraseLocation
    }

    @objc static var userPhrasesDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("data.txt")
    }

    @objc static var userPhrasesDataPathPlainBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("data-plain-bpmf.txt")
    }

    @objc static var excludedPhrasesDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("exclude-phrases.txt")
    }

    @objc static var excludedPhrasesDataPathPlainBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("exclude-phrases-plain-bpmf.txt")
    }

    @objc static var phraseReplacementDataPathMcBopomofo: String {
        (dataFolderPath as NSString).appendingPathComponent("phrases-replacement.txt")
    }

    @objc static var phraseReplacementEnabled: Bool {
        get { engineMcBopomofo.phraseReplacementEnabled }
        set { engineMcBopomofo.phraseReplacementEnabled = newValue }
    }

    @objc static func checkIfUserDataFolderExists() -> Bool {
        let folder = dataFolderPath
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder, isDirectory: &isDir)
        if exists && !isDir.boolValue {
            try? FileManager.default.removeItem(atPath: folder)
        }
        if !FileManager.default.fileExists(atPath: folder) {
            do {
                try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return false
            }
        }
        return true
    }

    private static func ensureFileExists(path: String, templateName: String, ext: String) -> Bool {
        guard !FileManager.default.fileExists(atPath: path) else {
            return true
        }
        let templateURL = Bundle.main.url(forResource: templateName, withExtension: ext)
        let data: Data = (try? Data(contentsOf: templateURL ?? URL(fileURLWithPath: ""))) ?? Data()
        return FileManager.default.createFile(atPath: path, contents: data, attributes: nil)
    }

    @objc static func checkIfUserLanguageModelFilesExist() -> Bool {
        guard checkIfUserDataFolderExists() else { return false }
        guard ensureFileExists(path: userPhrasesDataPathMcBopomofo, templateName: kUserDataTemplateName, ext: kTemplateExtension) else { return false }
        guard ensureFileExists(path: userPhrasesDataPathPlainBopomofo, templateName: kUserDataPlainBopomofoTemplateName, ext: kTemplateExtension) else { return false }
        guard ensureFileExists(path: excludedPhrasesDataPathMcBopomofo, templateName: kExcludedPhrasesMcBopomofoTemplateName, ext: kTemplateExtension) else { return false }
        guard ensureFileExists(path: excludedPhrasesDataPathPlainBopomofo, templateName: kExcludedPhrasesPlainBopomofoTemplateName, ext: kTemplateExtension) else { return false }
        guard ensureFileExists(path: phraseReplacementDataPathMcBopomofo, templateName: kPhraseReplacementTemplateName, ext: kTemplateExtension) else { return false }
        return true
    }

    @objc(checkIfUserPhraseExist:key:)
    static func checkIfExist(userPhrase: String, key: String) -> Bool {
        let unigrams = engineMcBopomofo.getUnigrams(reading: key)
        return unigrams.contains(where: { $0.value == userPhrase })
    }

    private static func checkIfPhrase(_ phrase: String, existAtPath path: String) -> Bool {
        let components = phrase.components(separatedBy: " ")
        guard components.count == 2, FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        let exactPhrase = components[0]
        let key = components[1]
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.components(separatedBy: " ")
            if parts.count == 2 && parts[0] == exactPhrase && parts[1] == key {
                return true
            }
        }
        return false
    }

    private static func writePhrase(_ phrase: String, atEndOfPath path: String) -> Bool {
        var addLineBreak = false
        if let attr = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attr[.size] as? UInt64, fileSize > 0,
           let handle = FileHandle(forReadingAtPath: path) {
            handle.seek(toFileOffset: fileSize - 1)
            let data = handle.readDataToEndOfFile()
            if let byte = data.first, byte != 0x0A {
                addLineBreak = true
            }
            try? handle.close()
        }

        guard let writeHandle = FileHandle(forUpdatingAtPath: path) else {
            return false
        }
        writeHandle.seekToEndOfFile()
        var textToWrite = addLineBreak ? "\n" : ""
        textToWrite += phrase + "\n"
        if let data = textToWrite.data(using: .utf8) {
            writeHandle.write(data)
        }
        try? writeHandle.close()
        return true
    }

    private static func removePhrase(_ phrase: String, atPath path: String) -> Bool {
        let components = phrase.components(separatedBy: " ")
        guard components.count == 2, FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        let exactPhrase = components[0]
        let key = components[1]
        let lines = content.components(separatedBy: "\n")
        var matched = false
        var remaining: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.components(separatedBy: " ")
            if parts.count == 2 && parts[0] == exactPhrase && parts[1] == key {
                matched = true
                continue
            }
            remaining.append(line)
        }

        if matched {
            let newContent = remaining.joined(separator: "\n")
            try? newContent.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        }
        return false
    }

    @discardableResult
    @objc static func writeUserPhrase(_ userPhrase: String) -> Bool {
        guard checkIfUserLanguageModelFilesExist() else { return false }
        _ = removePhrase(userPhrase, atPath: excludedPhrasesDataPathMcBopomofo)
        let includePath = userPhrasesDataPathMcBopomofo
        if checkIfPhrase(userPhrase, existAtPath: includePath) {
            return false
        }
        return writePhrase(userPhrase, atEndOfPath: includePath)
    }

    @objc static func removeUserPhrase(_ userPhrase: String) -> Bool {
        guard checkIfUserLanguageModelFilesExist() else { return false }
        let includePath = userPhrasesDataPathMcBopomofo
        _ = removePhrase(userPhrase, atPath: includePath)
        let excludePath = excludedPhrasesDataPathMcBopomofo
        if checkIfPhrase(userPhrase, existAtPath: excludePath) {
            return false
        }
        return writePhrase(userPhrase, atEndOfPath: excludePath)
    }

    @objc(readingFor:)
    static func reading(for phrase: String) -> String? {
        if !engineMcBopomofo.isDataModelLoaded {
            loadDataModel(.bopomofo)
        }
        return engineMcBopomofo.getReading(for: phrase)
    }

    @objc(annotateVariantForCharacters:readings:)
    static func annotateVariant(characters inCharacters: String, readings inReadings: String) -> String {
        guard engineMcBopomofo.isVariantAnnotatorLoaded else {
            return inCharacters
        }
        let chars = inCharacters.map { String($0) }
        let readings = inReadings.split(separator: "-").map { String($0) }
        guard chars.count == readings.count else {
            return inCharacters
        }
        let result = engineMcBopomofo.annotateVariant(characters: chars, readings: readings)
        return result.annotatedString
    }
}
