import AppMacros
import Foundation
import Testing
import Tasking
import UIKit
import SwiftUI
@testable import Nibble

@Suite("Tab accessory notifications") @MainActor
struct LibraryNotificationsTests {
    @Test func presentationControlsEffectsDeadlineAndAtomicReplacement() throws {
        let effects = RecordingLibraryEffects()
        let notices = LibraryNotifications(effects: effects)
        notices.activate(.library)
        let context = notices.context(for: .library)
        let snippet = UUID()
        notices.publish("削除しました", subject: "長い対象名", undoID: snippet, context: context)
        let first = try #require(notices.notice)
        #expect(first.sourceTab == .library && first.duration == .seconds(6))
        #expect(effects.events.isEmpty && notices.feedback == 0)
        let deadline = try #require(notices.presented(id: first.id))
        #expect(deadline.duration(to: .now) < .seconds(-5))
        #expect(notices.presented(id: first.id) == deadline)
        #expect(effects.events == [.announce("長い対象名、削除しました")] && notices.feedback == 1)
        notices.publish("コピーしました", context: context)
        let second = try #require(notices.notice)
        #expect(second.id != first.id && second.undoID == nil && second.subject == nil)
        #expect(second.duration == .seconds(2))
        notices.publish("コピーしました", context: context)
        #expect(notices.notice?.id != second.id)
        #expect(notices.presented(id: first.id) == nil)
        #expect(effects.events.count == 1)
    }

    @Test func leavingPresentationDropsPendingResultsAndNeverReplays() {
        let notices = LibraryNotifications(effects: RecordingLibraryEffects())
        notices.activate(.library)
        let original = notices.context(for: .library)
        notices.publish("コピーしました", context: original)
        notices.activate(.search)
        #expect(notices.notice == nil)
        notices.publish("古い一覧の結果", context: original)
        #expect(notices.notice == nil)
        let search = notices.context(for: .search)
        notices.publish("検索の結果", context: search)
        notices.activate(nil) // Sheet or inactive scene.
        #expect(notices.notice == nil)
        notices.publish("シートの背後の結果", context: search)
        notices.activate(.search)
        notices.publish("復帰前の結果", context: search)
        #expect(notices.notice == nil)
        notices.activate(.library)
        notices.publish("再訪前の結果", context: original)
        #expect(notices.notice == nil)
    }

    @Test func oldExpiryCannotClearNewNoticeAndCancelledViewReusesDeadline() async throws {
        let notices = LibraryNotifications(effects: RecordingLibraryEffects())
        notices.activate(.library)
        let context = notices.context(for: .library)
        notices.publish("コピーしました", context: context)
        let old = try #require(notices.notice?.id)
        let deadline = try #require(notices.presented(id: old))
        let tasks = ViewTaskStore()
        tasks.start(id: "expiry", lifetime: .screenBound) { _ in await notices.expire(id: old) }
        try await Task.sleep(for: .milliseconds(10))
        tasks.cancel(lifetime: .screenBound)
        await tasks.waitForIdle()
        #expect(notices.notice?.id == old && notices.presented(id: old) == deadline)
        tasks.start(id: "expiry", lifetime: .screenBound) { _ in await notices.expire(id: old) }
        try await ContinuousClock().sleep(until: deadline.advanced(by: .milliseconds(-30)))
        notices.publish("コピーしました", context: context)
        let latest = try #require(notices.notice?.id)
        notices.presented(id: latest)
        await tasks.waitForIdle()
        #expect(notices.notice?.id == latest)
        await notices.expire(id: latest)
        #expect(notices.notice == nil)
    }

    @Test func copyAndDeleteCompleteWithoutWaitingForDisplayAndLateResultsAreDiscarded() async throws {
        let files = try TestDatabase(); defer { files.removeFiles() }
        let id = try await create(files.store, title: "対象", body: "原文")
        let store = PausedNotificationStore(base: files.store)
        let effects = RecordingLibraryEffects()
        let notices = LibraryNotifications(effects: effects)
        notices.activate(.library)
        let model = LibraryModel(store: store, effects: effects, notifications: notices)
        let tasks = ViewTaskStore()
        await store.pauseCopy()
        tasks.start(id: "copy", lifetime: .sceneBound) { _ in await model.copy(id) }
        await store.waitForPause()
        notices.activate(.search)
        await store.resume()
        await tasks.waitForIdle()
        #expect(effects.events == [.copy("原文")])
        #expect(notices.notice == nil && model.notice == nil)
        #expect(try await files.store.snippet(id).useCount == 1)
        notices.activate(.library)
        await store.pauseMutation()
        tasks.start(id: "delete", lifetime: .sceneBound) { _ in await model.delete(id) }
        await store.waitForPause()
        notices.activate(nil)
        await store.resume()
        await tasks.waitForIdle()
        #expect(try await files.store.snippet(id).deleted)
        notices.activate(.library)
        #expect(notices.notice == nil)
        await model.restore(id)
        let restored = try #require(notices.notice)
        #expect(restored.message == "元に戻しました" && restored.subject == "対象")
        #expect(effects.events == [.copy("原文")]) // Effects await actual presentation.
    }

    @Test func undoClaimsOnlyCurrentNoticeOnceAndReportsFailure() async throws {
        let files = try TestDatabase(); defer { files.removeFiles() }
        let first = try await create(files.store, title: "一つ目", body: "A")
        let second = try await create(files.store, title: "二つ目", body: "B")
        let store = PausedNotificationStore(base: files.store)
        let effects = RecordingLibraryEffects()
        let notices = LibraryNotifications(effects: effects)
        notices.activate(.library)
        let model = LibraryModel(store: store, effects: effects, notifications: notices)
        await model.delete(first)
        let oldID = try #require(notices.notice?.id)
        await model.delete(second)
        let id = try #require(notices.notice?.id)
        notices.presented(id: id)
        await model.undoNotice(oldID)
        #expect(try await files.store.snippet(first).deleted)
        #expect(try await files.store.snippet(second).deleted)
        await store.pauseMutation()
        let tasks = ViewTaskStore()
        tasks.start(id: "undo", lifetime: .sceneBound) { _ in await model.undoNotice(id) }
        await store.waitForPause()
        await model.undoNotice(id)
        #expect(notices.notice?.undoInProgress == true)
        await store.resume()
        await tasks.waitForIdle()
        #expect(try await files.store.snippet(first).deleted)
        #expect(try await !files.store.snippet(second).deleted)
        #expect(notices.notice?.subject == "二つ目" && notices.notice?.undoID == nil)
        #expect(await store.restoreCount == 1)
        await model.delete(first)
        let failureID = try #require(notices.notice?.id)
        notices.presented(id: failureID)
        _ = try await files.store.mutate(.permanentlyDelete, id: first)
        await model.undoNotice(failureID)
        #expect(model.failure?.title == "復元できませんでした")
        #expect(notices.notice?.id == failureID && notices.notice?.undoInProgress == false)
        #expect(notices.notice?.message == "削除しました")
    }
}

private actor PausedNotificationStore: LibraryStorage {
    let base: SnippetStore
    private var copyPaused = false
    private var mutationPaused = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private(set) var restoreCount = 0
    init(base: SnippetStore) { self.base = base }
    func pauseCopy() { copyPaused = true }
    func pauseMutation() { mutationPaused = true }
    func waitForPause() async {
        if continuation != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
    private func pause() async {
        await withCheckedContinuation { continuation = $0; arrival?.resume(); arrival = nil }
    }
    func savedBody(_ id: UUID) async throws -> String {
        if copyPaused { copyPaused = false; await pause() }
        return try await base.savedBody(id)
    }
    func mutate(_ mutation: SnippetMutation, id: UUID) async throws -> SnippetMutationResult {
        if case .restore = mutation { restoreCount += 1 }
        if mutationPaused { mutationPaused = false; await pause() }
        return try await base.mutate(mutation, id: id)
    }
    func library(_ request: LibraryRequest) async throws -> LibraryPage { try await base.library(request) }
    func recordUse(_ use: SnippetUse) async throws { try await base.recordUse(use) }
    func setPinned(_ pinned: Bool, id: UUID) async throws { try await base.setPinned(pinned, id: id) }
    func beginDraft(snippetID: UUID?, body: String) async throws -> Draft { try await base.beginDraft(snippetID: snippetID, body: body) }
    func editingDraft(for id: UUID) async throws -> Draft { try await base.editingDraft(for: id) }
    func draft(_ id: UUID) async throws -> Draft { try await base.draft(id) }
    func keepDraft(_ draft: Draft) async throws { try await base.keepDraft(draft) }
}

extension UIIntegrationTests {
    @Suite("Legacy tab accessory", .serialized) @MainActor
    struct LegacyAccessoryTests {
        @Test func legacyBridgeAttachesAndReleasesNativeAccessoryWithoutReplacingContent() async throws {
            let files = try TestDatabase(); defer { files.removeFiles() }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let effects = RecordingLibraryEffects()
            let notices = LibraryNotifications(effects: effects)
            notices.activate(.library)
            let model = LibraryModel(store: files.store, effects: effects, notifications: notices)
            let owner = LibraryTaskOwner()
            let host = UIHostingController(rootView: LegacyAccessoryFixture(notices: notices, model: model, owner: owner))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
            window.rootViewController = host; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            func tab(in controller: UIViewController) -> UITabBarController? {
                if let tab = controller as? UITabBarController { return tab }
                return controller.children.compactMap { tab(in: $0) }.first
            }
            try await Task.sleep(for: .milliseconds(150))
            let tabs = try #require(tab(in: host))
            let selected = try #require(tabs.selectedViewController)
            let initialInset = selected.view.safeAreaInsets.bottom
            #expect(tabs.bottomAccessory == nil)
            notices.publish("削除しました", subject: String(repeating: "長い題名", count: 30), undoID: UUID(), context: notices.context(for: .library))
            try await Task.sleep(for: .milliseconds(200))
            #expect(tabs.bottomAccessory != nil)
            #expect(tabs.selectedViewController === selected)
            #expect(notices.feedback == 1)
            notices.activate(nil)
            try await Task.sleep(for: .milliseconds(200))
            #expect(tabs.bottomAccessory == nil)
            #expect(tabs.selectedViewController === selected)
            #expect(abs(selected.view.safeAreaInsets.bottom - initialInset) < 1)
            #expect(notices.feedback == 1)
        }
    }
}

@Equatable
private struct LegacyAccessoryFixture: View {
    private let inputRevision = UUID()
    @SkipEquatable let notices: LibraryNotifications
    @SkipEquatable let model: LibraryModel
    @SkipEquatable let owner: LibraryTaskOwner
    var body: some View {
        TabView {
            Tab("一覧", systemImage: "list.bullet") {
                List(0..<100, id: \.self) { Text("行 \($0)") }
                    .background {
                        LegacyLibraryAccessory(notifications: notices, isEnabled: notices.notice != nil,
                                               all: model, search: model, taskOwner: owner)
                            .frame(width: 0, height: 0)
                    }
            }
            Tab("設定", systemImage: "gear") { Text("設定") }
        }
    }
}
