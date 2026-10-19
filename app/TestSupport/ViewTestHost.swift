import SwiftUI
import Testing
import UIKit
@testable import Nibble

@MainActor
final class ViewTestHost {
    let window: UIWindow
    let controller = UIHostingController(rootView: AnyView(EmptyView()))

    init() throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try #require(scenes.first, "A hosted test needs the application's window scene")
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    func show(_ content: AnyView, phase: ScenePhase = .active, scheme: ColorScheme = .light) {
        let configured = content.environment(\.scenePhase, phase)
            .environment(\.colorScheme, scheme)
        controller.rootView = AnyView(configured)
        controller.view.setNeedsLayout()
    }

    func find<T: UIView>(_ type: T.Type) -> T? {
        var pending: [UIView] = [controller.view]
        while let view = pending.popLast() {
            if let result = view as? T { return result }
            pending.append(contentsOf: view.subviews.reversed())
        }
        return nil
    }

    func close() {
        controller.rootView = AnyView(EmptyView())
        window.isHidden = true
        window.rootViewController = nil
    }

    func wait(fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column,
              _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            controller.view.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "The mounted UI did not satisfy its observable condition",
                     sourceLocation: SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column))
    }
}

@MainActor
final class WeakReference<Object: AnyObject> {
    weak var value: Object?
    init(_ value: Object?) { self.value = value }
}
