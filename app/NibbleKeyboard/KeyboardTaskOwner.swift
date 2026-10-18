import Tasking

@MainActor
final class KeyboardTaskOwner {
    private let tasks = ViewTaskStore()
    func startTask(_ item: SnippetSummary, as operation: KeyboardModel.Use, on model: KeyboardModel) {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { token in
            try token.check()
            await model.use(item, as: operation)
        }
    }
    func startTask(_ values: [VariableName: String], on model: KeyboardModel) {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { token in
            try token.check()
            await model.completeVariableUse(values: values)
        }
    }
    func startTask(on model: KeyboardModel) {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { token in
            try token.check()
            await model.togglePin()
        }
    }
    func endScreen() { tasks.cancel(lifetime: .screenBound) }
    func waitForIdle() async { await tasks.waitForIdle() }
}
