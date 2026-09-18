import AppMacros
import SwiftUI
import Tasking

@Equatable
struct KeyboardView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let globe: UIButton
    @State private var tasks = ViewTaskStore()

    var body: some View {
        VStack(spacing: 0) {
            Picker("スニペットの絞り込み", selection: Binding(get: { model.request.filter }, set: { model.select($0) })) {
                ForEach(KeyboardFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                        .accessibilityIdentifier("keyboard.filter.\(filter.rawValue)")
                }
            }
            .pickerStyle(.segmented)
            .padding(6)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
        }
        .tint(.primary)
        .task(id: model.loadID) { await model.refresh() }
        .onChange(of: model.loadID) { tasks.cancel(lifetime: .screenBound) }
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            ScrollView { Text(failure).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
        } else if let page = model.page, !page.items.isEmpty {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(page.items) { item in
                        HStack(spacing: 6) {
                            Button { startTask(item, as: .insert) } label: {
                                KeyboardRowContent(item: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .frame(minHeight: 48)
                            }
                            .buttonStyle(KeyboardKeyStyle())
                            .accessibilityLabel("\(item.displayTitle)を入力")
                            .accessibilityHint("保存済みの本文を入力先へ挿入します")
                            .accessibilityIdentifier("keyboard.insert.\(item.id)")
                            Button { startTask(item, as: .copy) } label: {
                                Image(systemName: model.hasFullAccess ? "doc.on.doc" : "lock.doc")
                                    .font(.body)
                                    .frame(width: 44, height: 48)
                            }
                            .buttonStyle(KeyboardKeyStyle())
                            .accessibilityLabel("\(item.displayTitle)をコピー")
                            .accessibilityHint(model.hasFullAccess ? "クリップボードへコピーします" : "フルアクセスの案内を表示します")
                            .accessibilityIdentifier("keyboard.copy.\(item.id)")
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
            .disabled(!model.isCurrent || model.isUsing)
            .overlay { if model.loading { ProgressView().accessibilityLabel("読み込み中") } }
        } else if model.loading {
            ProgressView().accessibilityLabel("読み込み中")
        } else {
            ScrollView {
                Text(model.request.filter == .pinned ? "ピン留めしたスニペットはありません。" : "nibbleでスニペットを保存すると、ここから入力できます。")
                    .foregroundStyle(.secondary).padding(16)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            if model.needsSwitchKey { KeyboardInputModeButton(button: globe).frame(width: 44, height: 44) }
            Text(model.message ?? "nibble")
                .font(.caption)
                .foregroundStyle(model.message == nil ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("keyboard.status")
            if model.request.offset > 0 || model.page?.hasMore == true {
                Button("前のページ", systemImage: "chevron.left") { model.movePage(forward: false) }
                    .disabled(!model.isCurrent || model.request.offset == 0)
                    .accessibilityIdentifier("keyboard.previous")
                Text("\(model.request.offset / KeyboardRequest.pageSize + 1)").font(.caption.monospacedDigit())
                    .accessibilityLabel("\(model.request.offset / KeyboardRequest.pageSize + 1)ページ目")
                Button("次のページ", systemImage: "chevron.right") { model.movePage(forward: true) }
                    .disabled(!model.isCurrent || model.page?.hasMore != true)
                    .accessibilityIdentifier("keyboard.next")
            }
            Button("更新", systemImage: "arrow.clockwise", action: model.requestReload)
                .accessibilityIdentifier("keyboard.refresh")
            Button("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down", action: model.dismiss)
                .accessibilityIdentifier("keyboard.dismiss")
        }
        .font(.body)
        .labelStyle(.iconOnly)
        .buttonStyle(KeyboardControlStyle())
        .padding(.horizontal, 10)
    }

    private func startTask(_ item: SnippetSummary, as use: KeyboardModel.Use) {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            await model.use(item, as: use)
        }
    }
}

@Equatable
private struct KeyboardRowContent: @MainActor EquatableBodyView {
    let item: SnippetSummary
    var equatableBody: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).font(.subheadline).lineLimit(1)
                Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

@Equatable
@MainActor
private struct KeyboardInputModeButton: UIViewRepresentable {
    private let inputRevision = UUID()
    @SkipEquatable let button: UIButton
    func makeUIView(context: Context) -> UIButton { button }
    func updateUIView(_ uiView: UIButton, context: Context) { }
}

private struct KeyboardControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44)
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.3)
    }
}

/// A neutral raised input target; the surrounding input plane belongs to UIKit.
private struct KeyboardKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(configuration.isPressed ? 0.12 : 0))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
