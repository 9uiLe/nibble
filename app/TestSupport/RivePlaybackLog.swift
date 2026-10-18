import Foundation
import RiveRuntime

final class RivePlaybackLog: RiveLog.Logger, @unchecked Sendable {
    struct Advance {
        let time: TimeInterval
        let delta: TimeInterval
    }
    private struct State {
        var messages: [String] = []
        var advances: [Advance] = []
    }
    private let lock = NSLock()
    private var state = State()
    var advances: [Advance] { lock.withLock { state.advances } }

    func reset() { lock.withLock { state = State() } }
    func count(_ text: String) -> Int {
        lock.withLock { state.messages.reduce(0) { $0 + ($1.contains(text) ? 1 : 0) } }
    }
    func debug(tag: RiveLog.Tag, _ message: @escaping () -> String) {
        let text = message()
        lock.withLock { state.messages.append(text) }
    }
    func trace(tag: RiveLog.Tag, _ message: @escaping () -> String) {
        guard tag == .view else { return }
        let text = message()
        let prefix = "[RiveUIView] Advancing state machine (dt="
        guard text.hasPrefix(prefix), text.hasSuffix(")"),
              let delta = Double(text.dropFirst(prefix.count).dropLast()) else { return }
        let entry = Advance(time: ProcessInfo.processInfo.systemUptime, delta: delta)
        lock.withLock { state.advances.append(entry) }
    }
    func notice(tag: RiveLog.Tag, _ message: @escaping () -> String) {}
    func info(tag: RiveLog.Tag, _ message: @escaping () -> String) {}
    func error(tag: RiveLog.Tag, error: (any Error)?, _ message: @escaping () -> String) {}
    func warning(tag: RiveLog.Tag, _ message: @escaping () -> String) {}
    func fault(tag: RiveLog.Tag, _ message: @escaping () -> String) {}
    func critical(tag: RiveLog.Tag, _ message: @escaping () -> String) {}
}
