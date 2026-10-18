import KeyboardValueConversion
import Testing

@Suite("Local Japanese value conversion")
@MainActor
struct JapaneseValueConverterTests {
    @Test
    func emptyInputHasNoCandidateAndCanBeReleasedWithoutLoadingAReading() {
        let converter = JapaneseValueConverter()
        #expect(converter.candidates(reading: "") == .noCandidates)
        converter.reset()
        converter.release()
        #expect(converter.candidates(reading: "") == .noCandidates)
    }

    @Test(arguments: [String(repeating: "a", count: 65), "a" + String(repeating: "\u{301}", count: 128)])
    func eitherInputLimitRejectsConversionWithoutReturningATruncatedCandidate(reading: String) {
        let converter = JapaneseValueConverter()
        #expect(converter.candidates(reading: reading) == .inputTooLong(JapaneseValueConverter.inputLimits))
    }

    @Test(arguments: [String(repeating: "a", count: 64), String(repeating: "𠮷", count: 64)])
    func theInclusiveCharacterAndByteLimitsStillAllowAConversionRequest(reading: String) {
        let converter = JapaneseValueConverter()
        if case .inputTooLong = converter.candidates(reading: reading) {
            Issue.record("An input at the documented inclusive limit must not be rejected as too long")
        }
        converter.release()
    }

    @Test
    func dictionaryConversionWorksAfterCompositionResetAndResourceRelease() {
        let converter = JapaneseValueConverter()
        for _ in 0..<2 {
            guard case let .candidates(candidates) = converter.candidates(reading: "にほんご") else {
                Issue.record("The bundled Japanese dictionary must return candidates")
                return
            }
            #expect(candidates.contains("日本語"))
            converter.reset()
            converter.release()
        }
    }
}
