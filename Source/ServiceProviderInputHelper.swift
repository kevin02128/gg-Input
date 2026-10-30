import Foundation
import SwiftEngine

@objc(ServiceProviderInputHelper)
final class ServiceProviderInputHelper: NSObject, ServiceProviderDelegate {
    private let grid: ReadingGrid

    override init() {
        self.grid = ReadingGrid(languageModel: LanguageModelManager.engineMcBopomofo)
        super.init()
    }

    func reset() {
        grid.clear()
    }

    func serviceProvider(_ provider: ServiceProvider, didRequestInsertReading reading: String) {
        _ = grid.insertReading(reading)
    }

    func serviceProvider(didRequestCommitting provider: ServiceProvider) -> String {
        let walk = grid.walk()
        let result = walk.valuesAsStrings.joined()
        reset()
        return result
    }

    func serviceProvider(didRequestReset provider: ServiceProvider) {
        reset()
    }

    func serviceProvider(_ provider: ServiceProvider, didRequestConvertReadingToHanyuPinyin reading: String) -> String {
        let syllable = BopomofoSyllable.fromComposed(string: reading)
        return syllable.toHanyuPinyin(includesTone: false, useVForUUmlaut: false)
    }
}
