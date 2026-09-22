import Foundation
import RiveRuntime

/// Bounded to one test, with locked storage because Rive logs from worker threads too.
final class RivePlaybackLog: RiveLog.Logger, @unchecked Sendable {
    struct Advance {
        let time: TimeInterval
        let delta: TimeInterval
    }
    private let lock = NSLock()
    private var messages: [String] = []
    private var frames: [Advance] = []
    var advances: [Advance] { lock.withLock { frames } }

    func reset() { lock.withLock { messages.removeAll(); frames.removeAll() } }
    func count(_ text: String) -> Int { lock.withLock { messages.filter { $0.contains(text) }.count } }
    func debug(tag: RiveLog.Tag, _ message: @escaping () -> String) {
        let value = message()
        lock.withLock { messages.append(value) }
    }
    func trace(tag: RiveLog.Tag, _ message: @escaping () -> String) {
        guard tag == .view else { return }
        let value = message()
        let prefix = "[RiveUIView] Advancing state machine (dt="
        guard value.hasPrefix(prefix), let delta = Double(value.dropFirst(prefix.count).dropLast()) else { return }
        let frame = Advance(time: ProcessInfo.processInfo.systemUptime, delta: delta)
        lock.withLock { frames.append(frame) }
    }
    func notice(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
    func info(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
    func error(tag: RiveLog.Tag, error: (any Error)?, _ message: @escaping () -> String) { }
    func warning(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
    func fault(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
    func critical(tag: RiveLog.Tag, _ message: @escaping () -> String) { }
}
