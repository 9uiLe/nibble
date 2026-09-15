import Foundation
import Tasking

/// Owns finite UI requests across presentation changes in the library scene.
/// Business operations remain directly awaitable on LibraryModel.
@MainActor
final class LibraryTaskOwner {
    private let tasks = ViewTaskStore()

    enum Action {
        case refresh, open(LibraryModel.EditorSource), copy(UUID), pin(SnippetSummary)
        case delete(UUID), restore(UUID), permanentlyDelete(UUID)

        var id: ActionID {
            switch self {
            case .refresh: "library.refresh"
            case .open: "library.open"
            case .copy: "library.copy"
            case .pin(let item): ActionID("library.pin.\(item.id)")
            case .delete(let id): ActionID("library.delete.\(id)")
            case .restore(let id): ActionID("library.restore.\(id)")
            case .permanentlyDelete(let id): ActionID("library.permanentlyDelete.\(id)")
            }
        }

        var lifetime: ActionLifetime {
            if case .open = self { return .screenBound }
            return .sceneBound
        }

        var policy: TaskStartPolicy {
            switch self {
            case .refresh, .copy: .cancelExisting
            default: .ignoreNew
            }
        }
    }

    @discardableResult
    func startTask(_ action: Action, on model: LibraryModel) -> TaskStartOutcome {
        tasks.start(id: action.id, lifetime: action.lifetime, policy: action.policy) { [weak model] cancellation in
            try cancellation.check()
            guard let model else { return }
            switch action {
            case .refresh: await model.refresh()
            case .open(let source): await model.open(source)
            case .copy(let id): await model.copy(id)
            case .pin(let item): await model.pin(item)
            case .delete(let id): await model.delete(id)
            case .restore(let id): await model.restore(id)
            case .permanentlyDelete(let id): await model.permanentlyDelete(id)
            }
        }
    }

    func endScreen() { tasks.cancel(lifetime: .screenBound) }
    func waitForIdle() async { await tasks.waitForIdle() }
}
