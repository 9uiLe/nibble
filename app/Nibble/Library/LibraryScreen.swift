import AppMacros
import SwiftUI

@MainActor @Equatable
struct LibraryScreen: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let searchFocused: FocusState<Bool>.Binding
    var noticesPresented = false
    @SkipEquatable let openSettings: () -> Void
    init(model: LibraryModel, searchFocused: FocusState<Bool>.Binding, noticesPresented: Bool = false, openSettings: @escaping () -> Void = {}) {
        self.model = model; self.searchFocused = searchFocused; self.noticesPresented = noticesPresented; self.openSettings = openSettings
    }
    @State private var owner = LibraryTaskOwner()
    @State private var erasing: SnippetSummary?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(spacing: 12) {
            if model.surface == .library { RootScreenHeading(openSettings: openSettings) }
            LibrarySearchBar(model: model, searchFocused: searchFocused).padding(.horizontal, 20)
            if model.surface == .library && !model.isSearching {
                LibraryFilterBar(selection: Binding(get: { model.filter }, set: { model.filter = $0 }), counts: model.snapshot?.page.counts)
                    .padding(.horizontal, 20)
            }
            List {
                if let failure = model.failure { LibraryFailureSection(failure: failure, model: model, taskOwner: owner).listRowSeparator(.hidden) }
                if model.loading { Text(model.loadingTitle).font(.nibbleBody).accessibilityIdentifier("library.loading") }
                if model.loadingInterrupted {
                    Button("読み込みを再開") { owner.startTask(.refresh, on: model) }.font(.nibbleTitle).frame(minHeight: 44)
                }
                if model.showsEmptyState { LibraryEmptyState(model: model).listRowSeparator(.hidden) }
                if model.includesDrafts && !model.drafts.isEmpty {
                    switch model.filter {
                    case .all:
                        ForEach(model.drafts) { draft in
                            DraftResumeRow(draft: draft, model: model, taskOwner: owner).disabled(!model.contentIsCurrent)
                        }
                    default:
                        Section {
                            ForEach(model.drafts) { draft in
                                DraftListRow(draft: draft, model: model, taskOwner: owner).disabled(!model.contentIsCurrent)
                            }
                        } header: {
                            Text(model.contentRequest.sectionTitle)
                        } footer: {
                            Text("保存すると、コピーやキーボード入力に使えます。").font(.nibbleBody)
                        }
                    }
                    if model.filter == .all && model.page.counts.drafts > model.drafts.count {
                        Button("ほか\(model.page.counts.drafts - model.drafts.count)件の下書き") { model.filter = .drafts }
                            .font(.nibbleTitle).frame(minHeight: 44).accessibilityIdentifier("library.moreDrafts").disabled(!model.contentIsCurrent)
                    }
                }
                if !model.items.isEmpty {
                    Section {
                        ForEach(model.items) { row in
                            SnippetRow(item: row, isTrash: model.surface == .deleted, unusedSince: model.unusedSince(for: row), model: model, taskOwner: owner) { erasing = row }.disabled(!model.contentIsCurrent)
                        }
                    } header: {
                        if model.surface == .library { Text("\(model.contentRequest.sectionTitle)・コピー回数順").font(.caption) }
                    }
                }
                if model.hasMore {
                    Button("さらに表示") { model.showMore() }.font(.nibbleTitle).frame(minHeight: 44).accessibilityIdentifier("library.more")
                }
            }
            .id(model.contentRequest.filter)
            .listStyle(.plain).scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 44)
            .refreshable { await model.reload() }
            .modifier(LibraryNoticeOverlay(model: model, taskOwner: owner, isPresented: noticesPresented))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.surface == .library && !searchFocused.wrappedValue {
                Button { owner.startTask(.open(.new), on: model) } label: { Label("新規作成", systemImage: "plus") }
                    .buttonStyle(IOSButtonStyle()).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.nibbleCanvas).accessibilityIdentifier("library.add")
            }
        }
        .background(Color.nibbleCanvas).foregroundStyle(Color.nibblePrimary)
        .toolbarVisibility(model.surface == .library ? .hidden : .visible, for: .navigationBar)
        .task(id: model.readDemand) { if model.readDemand != nil { await model.refresh() } }
        .onAppear { if model.refreshOnAppearance { owner.startTask(.reload, on: model) } }
        .onDisappear { owner.endScreen() }
        .onChange(of: phase) {
            if phase == .background { owner.endScreen() }
            if phase == .active && model.refreshOnAppearance { owner.startTask(.reload, on: model) }
        }
        .alert("完全に削除しますか？", isPresented: Binding(get: { erasing != nil }, set: { if !$0 { erasing = nil } })) {
            Button("完全に削除", role: .destructive) {
                if let row = erasing { owner.startTask(.permanentlyDelete(row.id), on: model) }
                erasing = nil
            }.accessibilityIdentifier("library.confirmPermanentDelete")
            Button("取消", role: .cancel) { erasing = nil }.accessibilityIdentifier("library.cancelPermanentDelete")
        } message: {
            Text("\(erasing?.displayTitle ?? "")と関連する下書きを削除します。元に戻せません。")
        }
    }
}
