import AppMacros
import SwiftUI
import Tasking

@Equatable
struct KeyboardView: View {
    private let inputRevision = UUID()
    @SkipEquatable let model: KeyboardModel
    @SkipEquatable let globe: UIButton
    @State private var tasks = ViewTaskStore()
    @AccessibilityFocusState private var focusedControl: String?
    @State private var detailOrigin: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                browse
                    .opacity(model.detail == nil ? 1 : 0)
                    .allowsHitTesting(model.detail == nil)
                    .accessibilityHidden(model.detail != nil)
                if let detail = model.detail { preview(detail) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
        }
        .tint(Color(uiColor: .systemBlue))
        .task(id: model.loadID) { await model.refresh() }
        .task(id: model.detail?.id) { await model.loadDetail() }
        .task(id: model.notice?.id) {
            if let id = model.notice?.id { await model.expireNotice(id: id) }
        }
        .onChange(of: model.notice?.id) {
            if let message = model.message { AccessibilityNotification.Announcement(message).post() }
        }
        .onChange(of: model.detail?.id) {
            if model.detail != nil {
                focusedControl = "back"
            } else if let detailOrigin, model.page?.items.contains(where: { $0.id == detailOrigin }) == true {
                focusedControl = "more.\(detailOrigin)"
            } else {
                focusedControl = "filter.\(model.request.filter.rawValue)"
            }
        }
        .onChange(of: model.loadID) { tasks.cancel(lifetime: .screenBound) }
        .onDisappear { tasks.cancel(lifetime: .screenBound) }
    }

    private var browse: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                filters
                Spacer(minLength: 0)
                Button("更新", systemImage: "arrow.clockwise", action: model.requestReload)
                    .labelStyle(.iconOnly)
                    .buttonStyle(KeyboardControlStyle())
                    .accessibilityIdentifier("keyboard.refresh")
            }
            .padding(.horizontal, 10)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 13))
                .clipShape(.rect(cornerRadius: 13))
                .padding(.horizontal, 10)
        }
    }

    // The compact segment surface sits inside two full-height 44pt touch targets.
    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            segments.fixedSize(horizontal: true, vertical: false)
            segments
        }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(KeyboardFilter.allCases, id: \.self) { filter in
                Button { model.select(filter) } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background {
                            if model.request.filter == filter {
                                RoundedRectangle(cornerRadius: 7).fill(Color(uiColor: .tertiarySystemBackground))
                            }
                        }
                        .padding(2)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.request.filter == filter ? .isSelected : [])
                .accessibilityIdentifier("keyboard.filter.\(filter.rawValue)")
                .accessibilityFocused($focusedControl, equals: "filter.\(filter.rawValue)")
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 9).fill(Color(uiColor: .quaternarySystemFill))
                .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("保存した項目の絞り込み")
    }

    @ViewBuilder private var content: some View {
        if let failure = model.failure {
            ScrollView { Text(failure).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
        } else if let page = model.page, !page.items.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(page.items) { item in
                        VStack(spacing: 0) {
                            row(item)
                            if item.id != page.items.last?.id { Divider().padding(.horizontal, 12) }
                        }
                    }
                }
            }
            .id(model.request)
            .disabled(!model.isCurrent || model.isUsing)
            .overlay { if model.loading { ProgressView().accessibilityLabel("読み込み中") } }
        } else if model.loading {
            ProgressView().accessibilityLabel("読み込み中")
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    Text(model.request.filter == .pinned ? "ピン留めした項目はありません" : "保存した項目はありません")
                        .font(.subheadline.weight(.semibold))
                    Text(model.request.filter == .pinned
                        ? "「すべて」で項目の「…」を開くと、ピン留めできます。"
                        : "nibbleで文章やURLを保存すると、ここから入力できます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding(16).frame(maxWidth: .infinity)
            }
        }
    }

    private func row(_ item: SnippetSummary) -> some View {
        HStack(spacing: 0) {
            Button { startTask(item, as: .insert) } label: {
                KeyboardRowContent(item: item)
                    .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.displayTitle)を入力")
            .accessibilityValue(item.pinned ? "ピン留め済み" : "")
            .accessibilityHint("保存した本文を入力中のアプリに挿入します")
            .accessibilityIdentifier("keyboard.insert.\(item.id)")
            Button {
                detailOrigin = item.id
                model.openDetail(item)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18))
                    .frame(width: 44, height: 54).contentShape(Rectangle())
            }
            .accessibilityLabel("\(item.displayTitle)の全文と操作")
            .accessibilityIdentifier("keyboard.more.\(item.id)")
            .accessibilityFocused($focusedControl, equals: "more.\(item.id)")
        }
        .buttonStyle(KeyboardRowStyle())
        .background(model.notice?.insertedID == item.id ? Color(uiColor: .systemBlue).opacity(0.14) : .clear)
    }

    private func preview(_ detail: KeyboardModel.Detail) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("一覧に戻る", systemImage: "chevron.left", action: model.closeDetail)
                    .accessibilityIdentifier("keyboard.back")
                    .accessibilityFocused($focusedControl, equals: "back")
                Spacer(minLength: 0)
                Button { startTask() } label: {
                    Image(systemName: detail.item.pinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(detail.item.pinned ? "ピン留めを解除" : "ピン留め")
                .accessibilityValue(detail.item.pinned ? "ピン留め済み" : "")
                .accessibilityHint(model.hasFullAccess ? "" : "フルアクセスの案内を表示します")
                .accessibilityIdentifier("keyboard.pin")
                .disabled(model.isUsing || detail.body == nil)
            }
            .font(.subheadline).buttonStyle(KeyboardControlStyle())
            .padding(.horizontal, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(detail.item.displayTitle).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let body = detail.body {
                        Text(verbatim: body).font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("keyboard.detail.body")
                    } else if let failure = detail.failure {
                        Text(failure).font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ProgressView().accessibilityLabel("全文を読み込み中")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .id(detail.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 13))
            .clipShape(.rect(cornerRadius: 13))
            .padding(.horizontal, 10)
            HStack(spacing: 10) {
                Button { startTask(detail.item, as: .copy) } label: {
                    Label("コピー", systemImage: model.hasFullAccess ? "doc.on.doc" : "lock.doc")
                        .frame(minHeight: 44).padding(.horizontal, 12)
                        .background(Color(uiColor: .tertiarySystemBackground), in: .rect(cornerRadius: 10))
                }
                .accessibilityIdentifier("keyboard.copy.\(detail.item.id)")
                .accessibilityHint(model.hasFullAccess ? "本文をコピーします" : "フルアクセスの設定方法を表示します")
                Button { startTask(detail.item, as: .insert) } label: {
                    Text("入力する").fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.white)
                        .background(Color(uiColor: .systemBlue), in: .rect(cornerRadius: 10))
                }
                .accessibilityIdentifier("keyboard.detail.insert")
            }
            .font(.subheadline).buttonStyle(.plain)
            .disabled(model.isUsing || detail.body == nil || !model.isCurrent)
            .padding(.horizontal, 10).padding(.top, 6)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            if model.needsSwitchKey { KeyboardInputModeButton(button: globe).frame(width: 44, height: 44) }
            statusMessage
                .font(.caption)
                .foregroundStyle(model.message == nil ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("keyboard.status")
            if model.detail == nil, model.request.offset > 0 || model.page?.hasMore == true {
                Button("前のページ", systemImage: "chevron.left") { model.movePage(forward: false) }
                    .disabled(!model.isCurrent || model.isUsing || model.request.offset == 0)
                    .accessibilityIdentifier("keyboard.previous")
                Text("\(model.request.offset / KeyboardRequest.pageSize + 1)").font(.caption.monospacedDigit())
                    .accessibilityLabel("\(model.request.offset / KeyboardRequest.pageSize + 1)ページ目")
                Button("次のページ", systemImage: "chevron.right") { model.movePage(forward: true) }
                    .disabled(!model.isCurrent || model.isUsing || model.page?.hasMore != true)
                    .accessibilityIdentifier("keyboard.next")
            }
            Button("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down", action: model.dismiss)
                .accessibilityIdentifier("keyboard.dismiss")
        }
        .font(.body).foregroundStyle(.primary)
        .labelStyle(.iconOnly).buttonStyle(KeyboardControlStyle())
        .padding(.horizontal, 10)
    }

    @ViewBuilder private var statusMessage: some View {
        if let notice = model.notice, !notice.expires {
            ScrollView {
                Text(notice.message)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 72)
        } else {
            Text(model.message ?? "nibble").lineLimit(2)
        }
    }

    private func startTask(_ item: SnippetSummary, as use: KeyboardModel.Use) {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            await model.use(item, as: use)
        }
    }

    private func startTask() {
        tasks.start(id: "keyboard.use", lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            await model.togglePin()
        }
    }
}

@Equatable
private struct KeyboardRowContent: @MainActor EquatableBodyView {
    let item: SnippetSummary
    var equatableBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(item.displayTitle).font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if item.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            Text(item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.3)
    }
}

private struct KeyboardRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.10) : .clear)
            .opacity(isEnabled ? 1 : 0.45)
    }
}
