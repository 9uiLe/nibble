import Foundation
import RiveRuntime
import SwiftUI
import UIKit
import Testing
@testable import Nibble

/// Main-actor window hosting shared by serialized regression and performance suites.
@MainActor
final class RiveTestHost {
    let window: UIWindow
    let controller = UIHostingController(rootView: AnyView(EmptyView()))

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        window.rootViewController = controller
        window.isHidden = false
    }

    func show(_ content: AnyView, phase: ScenePhase = .active, scheme: ColorScheme = .light) {
        controller.rootView = AnyView(content.environment(\.scenePhase, phase)
            .environment(\.colorScheme, scheme).modifier(NibbleInterface()))
    }

    func close() {
        controller.rootView = AnyView(EmptyView())
        window.isHidden = true
        window.rootViewController = nil
    }

    func find<T: UIView>(_ type: T.Type) -> T? {
        func search(_ view: UIView) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { search($0) }.first
        }
        return search(controller.view)
    }

    func wait(sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath,
                                                             line: #line, column: #column),
              _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            controller.view.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Real Canvas did not reach its expected state within two seconds", sourceLocation: sourceLocation)
    }
}

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
