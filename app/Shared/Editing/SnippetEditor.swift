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
    @State private var showsPro = false
    @State private var focusBeforeHelp: EditorField?
    @State private var hasSetInitialFocus = false
    @State private var taskOwner = EditorTaskOwner()
    @FocusState private var focus: EditorField?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let complete: (@MainActor () -> Void)?
    @SkipEquatable private let proIsActive: () -> Bool
    @SkipEquatable private let proInformation: (@MainActor () -> AnyView)?

    init(draft: Draft, store: any DraftEditing, proIsActive: @escaping () -> Bool,
         proInformation: (@MainActor () -> AnyView)? = nil,
         complete: (@MainActor () -> Void)? = nil) {
        _model = State(initialValue: EditorModel(draft: draft, store: store))
        self.proIsActive = proIsActive
        self.proInformation = proInformation
        self.complete = complete
    }

    var body: some View {
        let snapshot = model.draft
        NavigationStack {
            VStack(spacing: 0) {
                EditorExitGuidance(isShared: complete != nil)
                ScrollView {
                    EditorForm(model: model, focus: $focus, taskOwner: taskOwner, isShared: complete != nil,
                               proIsActive: proIsActive,
                               showPro: proInformation == nil ? nil : { focus = nil; showsPro = true })
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focus == nil {
                    EditorBottomBar(model: model, confirmsDiscard: $confirmsDiscard, showHelp: showHelp)
                } else {
                    EditorKeyboardAccessory(focus: $focus, showHelp: showHelp)
                }
            }
            .background { Color.nibbleCanvas.ignoresSafeArea() }
            .navigationTitle(complete != nil ? "共有から保存" : model.draft.target == .new ? "新規作成" : "項目を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditorToolbar(model: model, taskOwner: taskOwner)
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
            .sheet(isPresented: $showsPro) {
                if let proInformation { proInformation() }
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
            if complete == nil && model.draft.target == .new && model.title.isEmpty && model.body.isEmpty {
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
