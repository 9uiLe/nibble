import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

@MainActor
public final class JapaneseValueConverter {
    public struct InputLimits: Equatable, Sendable {
        public let maximumCharacters: Int
        public let maximumUTF8Bytes: Int
    }

    public enum CandidateResult: Equatable, Sendable {
        case candidates([String])
        case inputTooLong(InputLimits)
        case noCandidates
    }

    public static let inputLimits = InputLimits(maximumCharacters: 64, maximumUTF8Bytes: 256)

    private var converter: KanaKanjiConverter?
    private let options: ConvertRequestOptions

    public init() {
        options = ConvertRequestOptions(
            N_best: 10,
            needTypoCorrection: false,
            requireJapanesePrediction: false,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: false,
            learningType: .nothing,
            maxMemoryCount: 0,
            shouldResetMemory: false,
            memoryDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent("nibble-disabled-conversion-learning"),
            sharedContainerURL: Bundle.main.bundleURL,
            textReplacer: .empty,
            specialCandidateProviders: [],
            zenzaiMode: .off,
            preloadDictionary: false,
            metadata: nil
        )
    }

    public func candidates(reading: String) -> CandidateResult {
        let limits = Self.inputLimits
        // Bound bytes before counting graphemes: a single grapheme may contain unbounded combining marks.
        guard reading.utf8.prefix(limits.maximumUTF8Bytes + 1).count <= limits.maximumUTF8Bytes else {
            return .inputTooLong(limits)
        }
        guard reading.count <= limits.maximumCharacters else { return .inputTooLong(limits) }
        guard !reading.isEmpty else { return .noCandidates }

        var input = ComposingText()
        input.insertAtCursorPosition(reading, inputStyle: .direct)
        let result = activeConverter().requestCandidates(input, options: options)
        let candidates = result.mainResults.filter { $0.inputable && !$0.text.isEmpty }.map(\.text)
        return candidates.isEmpty ? .noCandidates : .candidates(candidates)
    }

    public func reset() {
        converter?.stopComposition()
    }

    public func release() {
        reset()
        converter = nil
    }

    private func activeConverter() -> KanaKanjiConverter {
        if let converter { return converter }
        let created = KanaKanjiConverter.withDefaultDictionary(preloadDictionary: false)
        converter = created
        return created
    }
}
