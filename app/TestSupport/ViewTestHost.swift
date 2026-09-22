import SwiftUI
import UIKit
import Testing
@testable import Nibble

/// Main-actor window hosting shared by serialized regression and performance suites.
@MainActor
final class ViewTestHost {
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

    func wait(fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column,
              _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            controller.view.layoutIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Hosted view did not reach its expected state within two seconds",
                     sourceLocation: SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column))
    }
}
