import AppMacros
import SwiftUI
import ScopedAnimation

@Equatable
struct SnippetEditor: View {
    // Refresh parent-owned inputs even when the macro excludes their values.
    private let inputRevision = UUID()

    @State private var model: EditorModel
    @State private var confirmsDiscard = false
    @State private var showsHelp = false
    @State private var focusBeforeHelp: EditorField?
    @State private var hasSetInitialFocus = false
    @State private var taskOwner = EditorTaskOwner()
    @FocusState private var focus: EditorField?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let complete: (@MainActor () -> Void)?

    init(draft: Draft, store: any DraftEditing, complete: (@MainActor () -> Void)? = nil) {
        _model = State(initialValue: EditorModel(draft: draft, store: store))
        self.complete = complete
    }

    var body: some View {
        let snapshot = model.draft
        NavigationStack {
            ScrollView {
                EditorForm(model: model, focus: $focus, taskOwner: taskOwner, isShared: complete != nil)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focus == nil {
                    EditorExitGuidance(isShared: complete != nil)
                } else {
                    EditorKeyboardAccessory(focus: $focus, showHelp: showHelp)
                }
            }
            .background { Color.nibbleCanvas.ignoresSafeArea() }
            .navigationTitle(complete != nil ? "共有から保存" : model.draft.snippetID == nil ? "新規作成" : "項目を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(focus == nil ? .visible : .hidden, for: .bottomBar)
            .toolbar {
                EditorToolbar(model: model, taskOwner: taskOwner, focus: $focus,
                              confirmsDiscard: $confirmsDiscard, showHelp: showHelp)
            }
            .disabled(model.phase != .editing)
            .confirmationDialog("この下書きを破棄しますか？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("下書きを破棄", role: .destructive) {
                    taskOwner.startTask(.discard, on: model)
                }
                .accessibilityIdentifier("editor.confirmDiscard")
            } message: { Text("この下書きの内容は元に戻せません。保存済みの項目は変わりません。") }
            .sheet(isPresented: $showsHelp, onDismiss: { focus = focusBeforeHelp }) {
                EditorHelpView()
            }
        }
        .presentationBackground(Color.nibbleCanvas)
        .tint(.nibbleAccent)
        .detectAnimationLeaks()
        // Keep native presentation transactions outside app content; local scopes own its animation.
        .animationBarrier(warnsOnLeaks: false)
        .onAppear {
            guard !hasSetInitialFocus else { return }
            hasSetInitialFocus = true
            if complete == nil && model.draft.snippetID == nil && model.title.isEmpty && model.body.isEmpty {
                focus = .body
            }
        }
        .task(id: snapshot.sequence) {
            if snapshot.sequence > 0 { await model.persist(snapshot) }
        }
        .onChange(of: model.phase) {
            if model.phase == .finished {
                if let complete { complete() } else { dismiss() }
            }
        }
        .onDisappear { taskOwner.endScreen() }
        .interactiveDismissDisabled()
        .privacySensitive()
        .overlay {
            // A share extension has no app scene and can report background while visible.
            if complete == nil && scenePhase == .background {
                Color.nibbleCanvas.ignoresSafeArea().overlay { Text("nibble").font(.largeTitle.weight(.bold)) }
            }
        }
    }

    private func showHelp() {
        focusBeforeHelp = focus
        focus = nil
        showsHelp = true
    }
}
