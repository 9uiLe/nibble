import AppMacros
import SwiftUI
import Tasking

@MainActor @Equatable
struct WorkspaceDraftsView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: WorkspaceModel
    @State private var tasks = ViewTaskStore()

    var body: some View {
        List {
            Section {
                Text("作業中の内容は、保存済みの文章やコピーする内容と分けて保持しています。再開して保存・利用・破棄を選べます。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(model.drafts) { draft in
                Button { startTask(draft) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: WorkspacePresentation.draftTitle(draft))
                        Text(draft.modifiedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("workspace.draft.\(draft.id.uuidString)")
            }
            if model.drafts.isEmpty { Text("作業中の文章はありません") }
        }
        .navigationTitle("作業中")
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private func startTask(_ draft: WorkDraft) {
        tasks.start(id: "workspace.resume", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            await model.resume(draft)
        }
    }
}
