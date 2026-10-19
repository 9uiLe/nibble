import AppMacros
import SwiftUI

@Equatable
struct WorkspaceErrorView: @MainActor EquatableBodyView {
    let error: WorkspaceError
    var equatableBody: some View {
        Label {
            Text(WorkspacePresentation.error(error))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.red)
        .accessibilityIdentifier("workspace.error")
    }
}
