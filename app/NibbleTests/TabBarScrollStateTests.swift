import SwiftUI
import Testing
@testable import Nibble

@MainActor
struct TabBarScrollStateTests {
    @Test func changesSizeOnlyAfterIntentionalTravel() {
        let state = TabBarScrollState()
        state.beginGesture()
        state.observe(from: 0, to: 23, phase: .interacting)
        #expect(!state.isCompact)
        state.observe(from: 23, to: 24, phase: .interacting)
        #expect(state.isCompact)
        state.observe(from: 24, to: 10, phase: .interacting)
        #expect(state.isCompact)
        state.observe(from: 10, to: 8, phase: .interacting)
        #expect(!state.isCompact)
    }

    @Test func ignoresProgrammaticMovementAndRubberBandReversal() {
        let state = TabBarScrollState()
        state.observe(from: 0, to: 100, phase: .idle)
        #expect(!state.isCompact)
        state.beginGesture()
        state.observe(from: 0, to: 30, phase: .interacting)
        state.observe(from: 30, to: 80, phase: .decelerating)
        state.observe(from: 80, to: 0, phase: .decelerating)
        #expect(state.isCompact)
        state.beginGesture()
        state.observe(from: 80, to: 60, phase: .interacting)
        #expect(!state.isCompact)
    }

    @Test func tabChangeResetsAccumulatedTravel() {
        let state = TabBarScrollState()
        state.beginGesture()
        state.observe(from: 0, to: 40, phase: .interacting)
        state.expand()
        #expect(!state.isCompact)
        state.beginGesture()
        state.observe(from: 40, to: 41, phase: .interacting)
        #expect(!state.isCompact)
    }
}
