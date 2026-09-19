import AppMacros
import SwiftUI

/// Value-driven row; the screen decides how and when to execute each intent.
@Equatable
struct SnippetRow: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    enum Action { case edit, copy, pin, delete, restore, permanentlyDelete }
    let item: SnippetSummary
    let isTrash: Bool
    let actionsAtLeading: Bool
    var unusedSince: Date?
    let perform: (Action) -> Void

    private func copyButton(_ item: SnippetSummary) -> some View {
        Button { perform(.copy) } label: {
            Image(systemName: "doc.on.doc")
                .font(.body)
                .padding(8)
                .background(Color.nibbleAccent.opacity(0.07), in: .rect(cornerRadius: 10))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(item.displayTitle)をコピー")
        .accessibilityIdentifier("copy.\(item.id)")
    }

    private func rowActions(_ item: SnippetSummary) -> some View {
        HStack(spacing: 0) {
            if isTrash {
                Button { perform(.restore) } label: {
                    Image(systemName: "arrow.uturn.backward").font(.body)
                        .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(item.displayTitle)を復元")
                    .accessibilityIdentifier("restore.\(item.id)")
            } else { copyButton(item) }
            Menu { rowMenu(item) } label: {
                Image(systemName: "ellipsis").font(.body)
                    .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("\(item.displayTitle)のその他の操作")
            .accessibilityIdentifier("more.\(item.id)")
        }
    }

    private func rowLabel(_ item: SnippetSummary) -> some View {
        SnippetRowContent(title: item.title, preview: item.preview, pinned: item.pinned, unusedSince: unusedSince)
    }

    @ViewBuilder private func rowContent(_ item: SnippetSummary) -> some View {
        if isTrash {
            rowLabel(item)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.displayTitle)
                .accessibilityIdentifier("snippet.\(item.id)")
        } else {
            Button { perform(.edit) } label: { rowLabel(item) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snippet.\(item.id)")
                .accessibilityLabel(item.pinned ? "ピン留め、\(item.displayTitle)" : item.displayTitle)
                .accessibilityValue(unusedSince.map {
                    "30日以上未使用、最終使用日 " + $0.formatted(date: .numeric, time: .omitted)
                } ?? "")
                .accessibilityHint("編集します")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if actionsAtLeading { rowActions(item) }
            rowContent(item)
            if !actionsAtLeading { rowActions(item) }
        }
        .padding(.vertical, 4)
        .contextMenu { rowMenu(item) }
        .swipeActions(edge: .trailing, allowsFullSwipe: !isTrash) {
            if isTrash {
                Button("完全に削除", role: .destructive) { perform(.permanentlyDelete) }
            } else {
                Button("削除", systemImage: "trash", role: .destructive) { perform(.delete) }
                    .accessibilityIdentifier("swipe.delete.\(item.id)")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isTrash {
                Button(item.pinned ? "解除" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") {
                    perform(.pin)
                }
                .tint(.nibbleAccent)
                .accessibilityIdentifier("swipe.pin.\(item.id)")
            }
        }
    }

    @ViewBuilder private func rowMenu(_ item: SnippetSummary) -> some View {
        if isTrash {
            Button("復元", systemImage: "arrow.uturn.backward") { perform(.restore) }
            Button("完全に削除", systemImage: "trash", role: .destructive) { perform(.permanentlyDelete) }
                .accessibilityIdentifier("permanentlyDelete.\(item.id)")
        } else {
            Button("編集", systemImage: "square.and.pencil") { perform(.edit) }
            Button(item.pinned ? "ピン留めを外す" : "ピン留め", systemImage: item.pinned ? "pin.slash" : "pin") { perform(.pin) }
            Button("削除", systemImage: "trash", role: .destructive) { perform(.delete) }
                .accessibilityIdentifier("delete.\(item.id)")
        }
    }
}
