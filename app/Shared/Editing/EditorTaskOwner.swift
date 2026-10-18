import Tasking

@MainActor
final class EditorTaskOwner {
    private let tasks = ViewTaskStore()

    func startTask(_ operation: EditorModel.FinishOperation, on model: EditorModel) {
        tasks.start(id: "editor.finish", lifetime: .screenBound, policy: .ignoreNew) { token in
            try token.check()
            _ = await model.finish(operation)
        }
    }

    func endScreen() { tasks.cancel(lifetime: .screenBound) }
    func waitForIdle() async { await tasks.waitForIdle() }
}
