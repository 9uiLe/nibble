import AppMacros
import SwiftUI

@Equatable
struct LibraryFailureSection: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let failure: LibraryModel.Failure

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(failure.title, systemImage: "exclamationmark.circle")
                    .font(.headline).foregroundStyle(.primary)
                    .accessibilityIdentifier("library.error")
                Text(failure.message).font(.callout).foregroundStyle(.primary)
                switch failure.recovery {
                case .reload:
                    Button("一覧を再読み込み") { taskOwner.startTask(.reload, on: model) }
                        .font(.nibbleTitle)
                        .buttonStyle(.bordered).controlSize(.regular)
                        .accessibilityIdentifier("library.reload")
                case .retryUsage:
                    Button("回数と日時を記録し直す") { taskOwner.startTask(.retryUsage, on: model) }
                        .font(.nibbleTitle)
                        .buttonStyle(.bordered).controlSize(.regular)
                        .accessibilityIdentifier("library.retryUsage")
                case .retryRestore(let id):
                    Button("もう一度復元する") { taskOwner.startTask(.restore(id), on: model) }
                        .font(.nibbleTitle)
                        .buttonStyle(.bordered).controlSize(.regular)
                        .disabled(model.restoringIDs.contains(id))
                        .accessibilityIdentifier("library.retryRestore")
                case .dismiss:
                    Button { model.dismissFailure() } label: {
                        Label("閉じる", systemImage: "xmark")
                            .modifier(IconControlStyle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.dismissFailure")
                }
            }
            .padding(.vertical, 8)
        }
    }
}
