import Tasking

/// Insertion, copying and pinning share one screen-bound operation slot.
@MainActor
final class KeyboardTaskOwner {
    private let tasks = ViewTaskStore()

    func startTask(_ item: SnippetSummary, as use: KeyboardModel.Use, on model: KeyboardModel) {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            await model.use(item, as: use)
        }
    }

    func startTask(_ values: [String: String], on model: KeyboardModel) {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            await model.completeVariableUse(values: values)
        }
    }

    func startTask(on model: KeyboardModel) {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            await model.togglePin()
        }
    }

    func endScreen() { tasks.cancel(lifetime: .screenBound) }
    func waitForIdle() async { await tasks.waitForIdle() }
}
