import SwiftUI
import Observation

@MainActor
@Observable
final class TabBarScrollState {
    private(set) var isCompact = false
    @ObservationIgnored private var travel = 0
    @ObservationIgnored private var gestureDirection = 0

    func expand() {
        isCompact = false
        travel = 0
    }

    func beginGesture() {
        travel = 0
        gestureDirection = 0
    }

    func observe(from old: Int, to new: Int, phase: ScrollPhase) {
        guard phase == .interacting || phase == .decelerating else { return }
        let delta = new - old
        guard delta != 0 else { return }
        let direction = delta > 0 ? 1 : -1
        // Rubber-band settling reverses geometry without a new user gesture.
        if phase == .decelerating && direction != gestureDirection { return }
        gestureDirection = direction
        if new == 0 { expand(); return }
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if travel >= 24 { isCompact = true }
        else if travel <= -16 { isCompact = false }
    }
}
