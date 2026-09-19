import Foundation
import Observation
import OSLog

/// One tab-scoped result, independent of the lifetime of accepted storage writes.
@MainActor @Observable
final class LibraryNotifications {
    enum SourceTab: Equatable { case library, search }

    struct Context: Equatable {
        fileprivate let generation: UUID
        let sourceTab: SourceTab
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let sourceTab: SourceTab
        let message: String
        let subject: String?
        let undoID: UUID?
        var undoInProgress = false
        var duration: Duration { undoID == nil ? .seconds(2) : .seconds(6) }
        var announcement: String { subject.map { "\($0)、\(message)" } ?? message }
    }

    private let effects: any LibraryEffects
    private var generation = UUID()
    private var activeTab: SourceTab?
    private var presented: (id: UUID, deadline: ContinuousClock.Instant)?
    private(set) var notice: Notice?
    private(set) var feedback = 0

    init(effects: any LibraryEffects) { self.effects = effects }

    /// A changed presentation invalidates even results that have not completed yet.
    func activate(_ tab: SourceTab?) {
        guard activeTab != tab else { return }
        activeTab = tab
        generation = UUID()
        notice = nil
        presented = nil
    }

    func context(for tab: SourceTab) -> Context? {
        guard activeTab == tab else { return nil }
        return Context(generation: generation, sourceTab: tab)
    }

    func publish(_ message: String, subject: String? = nil, undoID: UUID? = nil, context: Context?) {
        guard let context, context == self.context(for: context.sourceTab) else { return }
        notice = Notice(sourceTab: context.sourceTab, message: message, subject: subject, undoID: undoID)
        presented = nil
    }

    /// Called by the mounted accessory. Redraws reuse its original deadline and effects.
    @discardableResult
    func presented(id: UUID) -> ContinuousClock.Instant? {
        guard let notice, notice.id == id else { return nil }
        if let presented, presented.id == id { return presented.deadline }
        let deadline = ContinuousClock.now.advanced(by: notice.duration)
        presented = (id, deadline)
        effects.announce(notice.announcement)
        feedback += 1
        return deadline
    }

    func expire(id: UUID) async {
        guard let presented, presented.id == id else { return }
        do {
            try await ContinuousClock().sleep(until: presented.deadline)
            try Task.checkCancellation()
            guard notice?.id == id else { return }
            notice = nil
            self.presented = nil
        } catch is CancellationError { }
        catch {
            Logger(subsystem: "nibble.9uiLe.com", category: "LibraryNotifications")
                .error("Notification timer failed; dismissing its current notice.")
            guard notice?.id == id else { return }
            notice = nil
            self.presented = nil
        }
    }

    /// Claim the visible notice, not a row or a previously captured snippet identifier.
    func claimUndo(noticeID: UUID) -> (snippetID: UUID, context: Context)? {
        guard let value = notice, value.id == noticeID, !value.undoInProgress,
              let snippetID = value.undoID, let context = context(for: value.sourceTab) else { return nil }
        notice?.undoInProgress = true
        return (snippetID, context)
    }

    func undoFailed(noticeID: UUID) {
        guard notice?.id == noticeID else { return }
        notice?.undoInProgress = false
    }
}
