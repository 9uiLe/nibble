import AppMacros
import SwiftUI

@Equatable
struct LibraryList: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    private var surface: LibrarySurface { model.surface }
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    @Binding var permanentDeletion: SnippetSummary?

    var body: some View {
        List {
            Group {
                if let failure = model.failure { LibraryFailureSection(model: model, taskOwner: taskOwner, failure: failure) }
                if model.loadingInterrupted {
                    Button { taskOwner.startTask(.refresh, on: model) } label: {
                        Label("読み込みを再開", systemImage: "arrow.clockwise")
                            .font(.nibbleTitle)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("library.resumeLoading")
                }
                if searchPrompt {
                    if model.loading { LibraryLoadingRow(title: surface.showsFilters ? "\(model.filter.title)を読み込み中" : "読み込み中") }
                    ContentUnavailableView {
                        Label {
                            Text("保存した項目を検索").font(.nibbleTitle)
                        } icon: {
                            Image(systemName: "magnifyingglass")
                        }
                    } description: {
                        Text("タイトルや本文の言葉で探せます。")
                            .font(.nibbleBody)
                    }
                        .accessibilityIdentifier("search.prompt")
                        .listRowSeparator(.hidden)
                } else {
                    if model.loading && !model.contentIsCurrent { LibraryLoadingRow(title: surface.showsFilters ? "\(model.filter.title)を読み込み中" : "読み込み中") }
                    if model.contentIsCurrent || model.loading || model.loadingInterrupted {
                        LibrarySections(model: model, taskOwner: taskOwner, showsFilters: surface.showsFilters, searchFocused: searchFocused, permanentDeletion: $permanentDeletion)
                            .disabled(!model.contentIsCurrent)
                    }
                    if model.contentIsCurrent && (model.hasMore || model.loading) {
                        Section {
                            if model.hasMore {
                                Button { model.showMore() } label: {
                                    Text("さらに表示")
                                        .font(.nibbleTitle)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .contentShape(.rect)
                                }
                                    .accessibilityIdentifier("library.loadMore")
                            }
                            if model.loading { LibraryLoadingRow(title: surface.showsFilters ? "\(model.filter.title)を読み込み中" : "読み込み中") }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .id(model.contentRequest.filter)
        .modifier(LibraryListStyle())
        .refreshable { await model.reload() }
        .scrollDismissesKeyboard(.interactively)
    }
    private var searchPrompt: Bool {
        surface.showsSearchPrompt && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
