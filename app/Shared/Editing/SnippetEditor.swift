import AppMacros
import ScopedAnimation
import SwiftUI

@Equatable
struct SnippetEditor: View {
    private let inputRevision = UUID()
    @State private var model: EditorModel
    @State private var owner = EditorTaskOwner()
    @State private var help = false
    @State private var discard = false
    @State private var initialFocusApplied = false
    @State private var suspendedFocus: EditorField?
    @FocusState private var focus: EditorField?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @SkipEquatable private let proIsActive: () -> Bool
    @SkipEquatable private let proInformation: (@MainActor () -> AnyView)?
    private let complete: (@MainActor () -> Void)?

    init(draft: Draft, store: any DraftEditing, proIsActive: @escaping () -> Bool,
         proInformation: (@MainActor () -> AnyView)? = nil, complete: (@MainActor () -> Void)? = nil) {
        _model = State(initialValue: EditorModel(draft: draft, store: store))
        self.proIsActive = proIsActive
        self.proInformation = proInformation
        self.complete = complete
    }

    var body: some View {
        let snapshot = model.draft
        NavigationStack {
            VStack(spacing: 0) {
                Text(complete == nil ? "閉じると下書きに残り、保存すると使えます。"
                     : "閉じると下書きを残して共有元へ。保存すると使えます。")
                    .font(.nibbleBody).foregroundStyle(Color.nibbleSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .accessibilityIdentifier("editor.exitGuidance")
                ScrollView {
                    EditorForm(model: model, focus: $focus, taskOwner: owner,
                               isShared: complete != nil, proIsActive: proIsActive)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorBottomBar(model: model, focus: $focus, confirmsDiscard: $discard) {
                    suspendedFocus = focus
                    focus = nil
                    help = true
                }
            }
            .navigationTitle(complete != nil ? "共有から保存" : model.draft.target == .new ? "新規作成" : "項目を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { owner.startTask(.keep, on: model) }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("editor.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { owner.startTask(.save, on: model) }
                        .fontWeight(.semibold).frame(minWidth: 44, minHeight: 44)
                        .disabled(!model.canSave).accessibilityIdentifier("editor.save")
                }
            }
            .disabled(model.phase != .editing)
            .background(Color.nibbleCanvas)
            .confirmationDialog("この下書きを破棄しますか？", isPresented: $discard, titleVisibility: .visible) {
                Button("下書きを破棄", role: .destructive) { owner.startTask(.discard, on: model) }
                    .accessibilityIdentifier("editor.confirmDiscard")
                Button("キャンセル", role: .cancel) {}
            } message: { Text("下書きは元に戻せません。保存済みの項目は変わりません。") }
            .sheet(isPresented: $help, onDismiss: { focus = suspendedFocus }) { EditorHelpView() }
        }
        .tint(.nibbleAccent)
        .presentationBackground(Color.nibbleCanvas)
        .animationBarrier(warnsOnLeaks: false)
        .interactiveDismissDisabled()
        .privacySensitive()
        .onAppear {
            guard !initialFocusApplied else { return }
            initialFocusApplied = true
            guard complete == nil, model.draft.target == .new, model.title.isEmpty, model.body.isEmpty else { return }
            focus = .body
        }
        .task(id: snapshot.sequence) {
            guard snapshot.sequence > 0 else { return }
            await model.persist(snapshot)
        }
        .onChange(of: model.phase) {
            guard model.phase == .finished else { return }
            guard let complete else { dismiss(); return }
            complete()
        }
        .onDisappear { owner.endScreen() }
        .overlay {
            if complete == nil && scenePhase == .background {
                Color.nibbleCanvas.ignoresSafeArea().overlay { Text("nibble").font(.largeTitle.bold()) }
            }
        }
    }
}
