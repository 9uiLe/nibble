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
            HStack(spacing: 8) {
                Picker("スニペットの絞り込み", selection: Binding(get: { model.request.filter }, set: { model.select($0) })) {
                    ForEach(KeyboardFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                            .accessibilityIdentifier("keyboard.filter.\(filter.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 260)
                Spacer(minLength: 0)
                Button("更新", systemImage: "arrow.clockwise", action: model.requestReload)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("keyboard.refresh")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
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
                LazyVStack(spacing: 0) {
                    ForEach(page.items) { item in
                        HStack(spacing: 0) {
                            Button { startTask(item, as: .insert) } label: {
                                KeyboardRowContent(item: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8).padding(.leading, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.displayTitle)を入力")
                            .accessibilityHint("保存済みの本文を入力先へ挿入します")
                            .accessibilityIdentifier("keyboard.insert.\(item.id)")
                            Button { startTask(item, as: .copy) } label: {
                                Image(systemName: model.hasFullAccess ? "doc.on.doc" : "lock.doc")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("\(item.displayTitle)をコピー")
                            .accessibilityHint(model.hasFullAccess ? "クリップボードへコピーします" : "フルアクセスの案内を表示します")
                            .accessibilityIdentifier("keyboard.copy.\(item.id)")
                        }
                        Divider().padding(.horizontal, 8)
                    }
                }
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
        VStack(spacing: 0) {
            if let message = model.message {
                Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 4)
                    .accessibilityIdentifier("keyboard.status")
            }
            HStack(spacing: 4) {
                if model.needsSwitchKey { KeyboardInputModeButton(button: globe).frame(width: 44, height: 44) }
                Text("nibble").font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("前のページ", systemImage: "chevron.left") { model.movePage(forward: false) }
                    .disabled(!model.isCurrent || model.request.offset == 0)
                    .accessibilityIdentifier("keyboard.previous")
                Text("\(model.request.offset / KeyboardRequest.pageSize + 1)").font(.caption.monospacedDigit())
                    .accessibilityLabel("\(model.request.offset / KeyboardRequest.pageSize + 1)ページ目")
                Button("次のページ", systemImage: "chevron.right") { model.movePage(forward: true) }
                    .disabled(!model.isCurrent || model.page?.hasMore != true)
                    .accessibilityIdentifier("keyboard.next")
                Button("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down", action: model.dismiss)
                    .accessibilityIdentifier("keyboard.dismiss")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(KeyboardControlStyle())
            .padding(.horizontal, 8)
        }
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                Text(item.displayTitle).fontWeight(.medium).lineLimit(1)
            }
            .font(.subheadline)
            Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
