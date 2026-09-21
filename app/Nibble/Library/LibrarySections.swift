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
        if displaysDrafts && model.contentRequest.filter == .all, let draft = model.drafts.first {
            DraftResumeRow(model: model, taskOwner: taskOwner, draft: draft)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 15, leading: 22, bottom: 4, trailing: 22))
        } else if displaysDrafts && !model.drafts.isEmpty {
            Section {
                ForEach(model.drafts) { draft in
                    DraftListRow(model: model, taskOwner: taskOwner, draft: draft)
                }
            } header: {
                Label("タップして、編集を再開", systemImage: "square.and.pencil")
                    .font(.nibbleBody).textCase(nil).padding(.vertical, 8)
            } footer: {
                Text("下書きは、編集画面で「保存」すると一覧やキーボードから使えます。")
                    .font(.nibbleBody).padding(.vertical, 16)
            }
        }
        if model.contentIsCurrent && contentIsEmpty && !model.loading && !model.loadingInterrupted && model.failure == nil {
            LibraryEmptyState(model: model, taskOwner: taskOwner, showsFilters: showsFilters, showsCreationCTA: showsCreationCTA)
        } else if model.contentRequest.filter != .drafts {
            Section {
                ForEach(model.items) { item in LibrarySnippetRow(model: model, taskOwner: taskOwner, item: item, searchFocused: searchFocused, permanentDeletion: $permanentDeletion) }
            } header: {
                if model.contentRequest.filter != .trash && !model.items.isEmpty {
                    HStack {
                        Text(sectionTitle).fontWeight(.semibold)
                        Spacer()
                        Label("使用回数順", systemImage: "arrow.down")
                    }
                    .font(.caption2)
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
    private var displaysDrafts: Bool { showsFilters && (model.contentRequest.filter == .all || model.contentRequest.filter == .drafts) }
    private var contentIsEmpty: Bool { model.items.isEmpty && (!displaysDrafts || model.drafts.isEmpty) }
    private var showsCreationCTA: Bool {
        showsFilters && (model.filter == .all || model.filter == .drafts)
            && model.contentIsCurrent && contentIsEmpty && !model.loading && !model.loadingInterrupted && model.failure == nil
    }
    private var sectionTitle: String {
        if model.contentRequest.filter == .trash { return "削除した項目" }
        return model.contentRequest.query.isEmpty ? (model.contentRequest.filter == .pinned ? "ピン留めした項目" : "保存した項目") : "検索結果"
    }
}
