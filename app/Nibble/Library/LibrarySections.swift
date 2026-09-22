import AppMacros
import SwiftUI

@Equatable
struct LibrarySections: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    let showsFilters: Bool
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    @Binding var permanentDeletion: SnippetSummary?

    var body: some View {
        if model.includesDrafts && model.contentRequest.filter == .all, let draft = model.drafts.first {
            DraftResumeRow(model: model, taskOwner: taskOwner, draft: draft)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
        } else if model.includesDrafts && !model.drafts.isEmpty {
            Section {
                ForEach(model.drafts) { draft in
                    DraftListRow(model: model, taskOwner: taskOwner, draft: draft)
                }
            } header: {
                Text("編集中の項目")
                    .font(.caption.weight(.semibold)).textCase(nil).padding(.vertical, 6)
            } footer: {
                Text("保存すると、コピーやキーボード入力に使えます。")
                    .font(.nibbleBody).foregroundStyle(.secondary).padding(.vertical, 8)
            }
        }
        if model.showsEmptyState {
            LibraryEmptyState(model: model)
        } else if model.contentRequest.filter != .drafts {
            Section {
                ForEach(model.items) { item in LibrarySnippetRow(model: model, taskOwner: taskOwner, item: item, searchFocused: searchFocused, permanentDeletion: $permanentDeletion) }
            } header: {
                if model.contentRequest.filter != .trash && !model.items.isEmpty {
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
        }
    }
    private var sectionTitle: String {
        if model.contentRequest.filter == .trash { return "削除した項目" }
        return model.contentRequest.query.isEmpty ? (model.contentRequest.filter == .pinned ? "ピン留めした項目" : "保存した項目") : "検索結果"
    }
}
