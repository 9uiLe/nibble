import Tasking

/// Owns one terminal operation at a time; the model owns persistence and its result.
@MainActor
final class EditorTaskOwner {
    private let tasks = ViewTaskStore()

    func startTask(_ operation: EditorModel.FinishOperation, on model: EditorModel) {
        tasks.start(id: "editor.finish", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            _ = await model.finish(operation)
        }
    }

    func endScreen() { tasks.cancel(lifetime: .screenBound) }
    func waitForIdle() async { await tasks.waitForIdle() }
}
