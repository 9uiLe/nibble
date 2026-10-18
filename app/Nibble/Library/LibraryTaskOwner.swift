import Foundation
import Tasking

@MainActor
final class LibraryTaskOwner {
    private let tasks = ViewTaskStore()
    private weak var presenting: LibraryModel?
    private var presentationID: UUID?
    enum Action {
        case refresh, reload, retryUsage, open(LibraryModel.EditorSource), copy(UUID)
        case completeVariableCopy(UUID, [VariableName: String]), pin(SnippetSummary)
        case delete(UUID), restore(UUID), undoNotice(UUID), permanentlyDelete(UUID)
        var identity: ActionID {
            switch self {
            case .refresh, .reload: "library.read"
            case .open: "library.editor"
            case .copy: "library.copy"
            case .completeVariableCopy: "library.variables"
            case .retryUsage: "library.record"
            case .pin(let row): ActionID("library.pin.\(row.id)")
            case .delete(let id): ActionID("library.delete.\(id)")
            case .restore(let id): ActionID("library.restore.\(id)")
            case .undoNotice(let id): ActionID("library.undo.\(id)")
            case .permanentlyDelete(let id): ActionID("library.erase.\(id)")
            }
        }
    }
    @discardableResult
    func startTask(_ action: Action, on model: LibraryModel) -> TaskStartOutcome {
        let request = UUID()
        let context = model.noticeContext
        let lifetime: ActionLifetime
        let policy: TaskStartPolicy
        switch action {
        case .open: lifetime = .screenBound; policy = .ignoreNew
        case .refresh, .reload, .copy: lifetime = .sceneBound; policy = .cancelExisting
        default: lifetime = .sceneBound; policy = .ignoreNew
        }
        return tasks.start(id: action.identity, lifetime: lifetime, policy: policy) { [weak self, weak model] cancellation in
            try cancellation.check()
            guard let model else { return }
            switch action {
            case .refresh: await model.refresh()
            case .reload: await model.reload()
            case .retryUsage: await model.retryUsageRecording()
            case .open(let target):
                self?.presenting = model
                self?.presentationID = request
                await model.open(target, requestID: request)
            case .copy(let id): await model.copy(id, context: context)
            case .completeVariableCopy(let id, let values): await model.completeVariableCopy(id: id, values: values)
            case .pin(let row): await model.pin(row)
            case .delete(let id): await model.delete(id, context: context)
            case .restore(let id): await model.restore(id, context: context)
            case .undoNotice(let id): await model.undoNotice(id, context: context)
            case .permanentlyDelete(let id): await model.permanentlyDelete(id, context: context)
            }
        }
    }
    func endScreen() {
        if let presentationID { presenting?.cancelOpening(id: presentationID) }
        presentationID = nil
        presenting = nil
        tasks.cancel(lifetime: .screenBound)
    }
    func waitForIdle() async { await tasks.waitForIdle() }
}
