import AppMacros
import SwiftUI

@Equatable
struct LibrarySections: View {
    private enum DraftContent {
        case resume(DraftSummary)
        case list([DraftSummary])
        case none
    }

    private enum ItemContent {
        case empty
        case items([SnippetSummary])
        case none
    }

    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    @Binding var permanentDeletion: SnippetSummary?

    private var draftContent: DraftContent {
        guard model.includesDrafts, !model.drafts.isEmpty else { return .none }
        if model.contentRequest.filter == .all, let draft = model.drafts.first { return .resume(draft) }
        return .list(model.drafts)
    }

    private var itemContent: ItemContent {
        if model.showsEmptyState { return .empty }
        if model.contentRequest.filter == .drafts { return .none }
        return .items(model.items)
    }

    var body: some View {
        switch draftContent {
        case .resume(let draft):
            DraftResumeRow(model: model, taskOwner: taskOwner, draft: draft)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
        case .list(let drafts):
            Section {
                ForEach(drafts) { draft in
                    DraftListRow(model: model, taskOwner: taskOwner, draft: draft)
                }
            } header: {
                Text("編集中の項目")
                    .font(.caption.weight(.semibold)).textCase(nil).padding(.vertical, 6)
            } footer: {
                Text("保存すると、コピーやキーボード入力に使えます。")
                    .font(.nibbleBody).foregroundStyle(.secondary).padding(.vertical, 8)
            }
        case .none:
            EmptyView()
        }
        switch itemContent {
        case .empty:
            LibraryEmptyState(model: model)
        case .items(let items):
            Section {
                ForEach(items) { item in LibrarySnippetRow(model: model, taskOwner: taskOwner, item: item, searchFocused: searchFocused, permanentDeletion: $permanentDeletion) }
            } header: {
                if model.contentRequest.filter != .trash && !items.isEmpty {
                    HStack {
                        Text(sectionTitle).fontWeight(.semibold)
                        Spacer()
                        Text("コピー回数順")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.vertical, 6)
                }
            }
            if model.contentRequest.filter == .trash {
                Text("削除した項目は自動で消えません。復元すると、一覧からまた使えます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .none:
            EmptyView()
        }
    }
    private var sectionTitle: String { model.contentRequest.sectionTitle }
}
