import Foundation
import Tasking

/// Owns finite UI requests across presentation changes in the library scene.
/// Business operations remain directly awaitable on LibraryModel.
@MainActor
final class LibraryTaskOwner {
    private let tasks = ViewTaskStore()
    private weak var openingModel: LibraryModel?
    private var openingID: UUID?

    enum Action {
        case refresh, reload, retryUsage, open(LibraryModel.EditorSource), copy(UUID), pin(SnippetSummary)
        case delete(UUID), restore(UUID), undoNotice(UUID), permanentlyDelete(UUID)

        var id: ActionID {
            switch self {
            case .refresh, .reload: "library.refresh"
            case .open: "library.open"
            case .copy: "library.copy"
            case .retryUsage: "library.usage.retry"
            case .pin(let item): ActionID("library.pin.\(item.id)")
            case .delete(let id): ActionID("library.delete.\(id)")
            case .undoNotice(let id): ActionID("library.undo.\(id)")
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
            case .refresh, .reload, .copy: .cancelExisting
            default: .ignoreNew
            }
        }
    }

    @discardableResult
    func startTask(_ action: Action, on model: LibraryModel) -> TaskStartOutcome {
        let requestID = UUID()
        return tasks.start(id: action.id, lifetime: action.lifetime, policy: action.policy) { [weak self, weak model] cancellation in
            try cancellation.check()
            guard let model else { return }
            switch action {
            case .refresh: await model.refresh()
            case .reload: await model.reload()
            case .open(let source):
                self?.openingModel = model
                self?.openingID = requestID
                await model.open(source, requestID: requestID)
            case .copy(let id): await model.copy(id)
            case .retryUsage: await model.retryUsageRecording()
            case .pin(let item): await model.pin(item)
            case .delete(let id): await model.delete(id)
            case .restore(let id): await model.restore(id)
            case .undoNotice(let id): await model.undoNotice(id)
            case .permanentlyDelete(let id): await model.permanentlyDelete(id)
            }
        }
    }

    func endScreen() {
        tasks.cancel(lifetime: .screenBound)
        if let openingID { openingModel?.cancelOpening(id: openingID) }
        openingModel = nil
        openingID = nil
    }
    func waitForIdle() async { await tasks.waitForIdle() }
}
