import Tasking

@MainActor
final class PreparedKeyboardTaskOwner {
    enum Action {
        case reload
        case select(PreparedCardSummary)
        case insert
    }

    private let tasks = ViewTaskStore()
    private let model: PreparedKeyboardModel

    init(model: PreparedKeyboardModel) { self.model = model }

    func startTask(_ action: Action) {
        switch action {
        case .reload:
            tasks.start(id: "prepared.keyboard.load", lifetime: .screenBound, policy: .cancelExisting) { [model] cancellation in
                try cancellation.check()
                await model.refresh()
            }
        case .select(let summary):
            tasks.start(id: "prepared.keyboard.use", lifetime: .screenBound, policy: .cancelExisting) { [model] cancellation in
                try cancellation.check()
                await model.select(summary)
            }
        case .insert:
            tasks.start(id: "prepared.keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { [model] cancellation in
                try cancellation.check()
                await model.insert()
            }
        }
    }

    func cancelUse() { tasks.cancel(lifetime: .screenBound) }

    func cancelAll() {
        cancelUse()
    }
}
