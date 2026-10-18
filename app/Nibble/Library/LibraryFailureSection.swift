import AppMacros
import SwiftUI

@MainActor @Equatable
struct LibraryFailureSection: View {
    private let inputRevision = UUID()
    let failure: LibraryModel.Failure
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IOSInlineAlert(failure.title, message: failure.message, variant: .error)
            switch failure.recovery {
            case .reload:
                Button("一覧を再読み込み") { taskOwner.startTask(.reload, on: model) }.accessibilityIdentifier("library.retry")
            case .retryUsage:
                Button("回数と日時を記録し直す") { taskOwner.startTask(.retryUsage, on: model) }.accessibilityIdentifier("library.retryUsage")
            case .retryRestore(let id):
                Button("もう一度復元する") { taskOwner.startTask(.restore(id), on: model) }
            case .dismiss:
                Button("閉じる") { model.dismissFailure() }
            }
        }.buttonStyle(IOSButtonStyle(.secondary, size: .compact))
    }
}
