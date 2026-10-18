import AppMacros
import SwiftUI

@MainActor @Equatable
struct SnippetRow: View {
    enum Action { case edit, copy, pin, delete, restore, permanentlyDelete }
    private let inputRevision = UUID()
    let item: SnippetSummary
    let isTrash: Bool
    var unusedSince: Date? = nil
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let taskOwner: LibraryTaskOwner
    @SkipEquatable let requestDeletion: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            switch isTrash {
            case true:
                SnippetRowContent(title: item.title, preview: item.preview, pinned: item.pinned)
                Button { taskOwner.startTask(.restore(item.id), on: model) } label: {
                    Label("復元", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(.rect)
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(item.displayTitle)を復元").accessibilityIdentifier("restore.\(item.id)")
                Button(role: .destructive) { requestDeletion() } label: {
                    Label("完全に削除", systemImage: "trash")
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(.rect)
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(item.displayTitle)を完全に削除").accessibilityIdentifier("permanentlyDelete.\(item.id)")
            case false:
                Button { taskOwner.startTask(.open(.snippet(item.id)), on: model) } label: {
                    HStack {
                        SnippetRowContent(title: item.title, preview: item.preview, pinned: item.pinned, unusedSince: unusedSince)
                        Image(systemName: "square.and.pencil").font(.caption).foregroundStyle(Color.nibbleSecondary)
                    }.contentShape(.rect)
                }.buttonStyle(.plain).accessibilityLabel((item.pinned ? "ピン留め、" : "") + item.displayTitle).accessibilityIdentifier("snippet.\(item.id)")
                Button { taskOwner.startTask(.copy(item.id), on: model) } label: {
                    Label("コピー", systemImage: "doc.on.doc").font(.caption).labelStyle(.titleAndIcon)
                        .frame(minWidth: 56, minHeight: 44).contentShape(.rect)
                        .background(Color.nibbleSoft, in: .rect(cornerRadius: 10))
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(item.displayTitle)の本文をコピー").accessibilityIdentifier("copy.\(item.id)")
                Menu {
                    Button("編集", systemImage: "square.and.pencil") { taskOwner.startTask(.open(.snippet(item.id)), on: model) }
                        .accessibilityIdentifier("edit.\(item.id)")
                    PinButton(pinned: item.pinned, action: { taskOwner.startTask(.pin(item), on: model) })
                    Button("削除", systemImage: "trash", role: .destructive) { taskOwner.startTask(.delete(item.id), on: model) }
                        .accessibilityIdentifier("delete.\(item.id)")
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(.rect) }
                .accessibilityLabel("\(item.displayTitle)のその他").accessibilityIdentifier("more.\(item.id)")
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isTrash { Button("削除", role: .destructive) { taskOwner.startTask(.delete(item.id), on: model) }.accessibilityIdentifier("swipe.delete.\(item.id)") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isTrash { PinButton(pinned: item.pinned, action: { taskOwner.startTask(.pin(item), on: model) }).accessibilityIdentifier("swipe.pin.\(item.id)") }
        }
        .contextMenu {
            if !isTrash {
                Button("編集") { taskOwner.startTask(.open(.snippet(item.id)), on: model) }
                    .accessibilityIdentifier("edit.\(item.id)")
                PinButton(pinned: item.pinned, action: { taskOwner.startTask(.pin(item), on: model) })
                Button("削除", role: .destructive) { taskOwner.startTask(.delete(item.id), on: model) }
                    .accessibilityIdentifier("delete.\(item.id)")
            }
        }
    }
}
