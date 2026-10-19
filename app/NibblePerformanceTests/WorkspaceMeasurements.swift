import Darwin
import Foundation
import SQLite3
import SwiftUI
import Testing
import UIKit
@testable import Nibble

@Suite("Workspace Release measurements", .serialized)
@MainActor
struct WorkspaceMeasurements {
    @Test func fiveThousandCardsSupportBoundedQueriesAndCompletePageScans() async throws {
        try requireWorkspaceReleaseBuild()
        let fixture = try MeasurementWorkspace()
        defer { fixture.removeFiles() }
        let publicDraft = try await fixture.repository.beginDraft(title: "公開経路サンプル", body: "公開 API で保存した原文\0か\u{3099}")
        let publicCard = try await fixture.repository.publish(publicDraft)
        try fixture.seedAdditionalCards(count: 4_999)
        let prepared = try await fixture.repository.list(query: WorkspaceQuery())
        #expect(prepared.total == 5_000)
        #expect(prepared.cards.count == 50 && prepared.hasMore)
        #expect(try await fixture.repository.card(id: publicCard.id).body.utf8.elementsEqual(publicCard.body.utf8))
        #expect(try await fixture.repository.list(query: WorkspaceQuery(query: "公開経路サンプル")).cards.map(\.id) == [publicCard.id])
        let queries: [(name: String, text: String, expectedTotal: Int)] = [
            ("width_case_match", "abc", 4_999),
            ("width_katakana_match", "ｶﾅ", 4_999),
            ("unique_literal_match", "%_\\唯一", 1),
            ("absent_match", "一致しない検索語", 0),
        ]
        var samples: [[String: Any]] = []
        for iteration in 0..<8 {
            for query in queries {
                let started = ProcessInfo.processInfo.systemUptime
                let result = try await fixture.repository.list(query: WorkspaceQuery(query: query.text))
                let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
                #expect(result.total == query.expectedTotal)
                #expect(result.cards.count <= 50)
                #expect(milliseconds <= 750, "A 50-card query exceeded the conservative 750 ms Release guardrail")
                samples.append([
                    "kind": "query", "iteration": iteration, "query": query.name,
                    "elapsed_ms": milliseconds, "rows_returned": result.cards.count, "total_matches": result.total,
                    "returned_title_body_utf8_bytes": result.cards.reduce(0) { $0 + $1.title.utf8.count + $1.body.utf8.count },
                    "physical_footprint_bytes": try workspacePhysicalFootprint(),
                ])
            }
        }
        for iteration in 0..<4 {
            var seen = Set<UUID>()
            var offset = 0
            var pages = 0
            var returnedBytes = 0
            let started = ProcessInfo.processInfo.systemUptime
            while true {
                let page = try await fixture.repository.list(query: WorkspaceQuery(offset: offset))
                #expect(page.total == 5_000 && page.cards.count <= 50)
                for card in page.cards {
                    #expect(seen.insert(card.id).inserted, "Pagination returned a duplicate card in an unchanged corpus")
                    returnedBytes += card.title.utf8.count + card.body.utf8.count
                }
                pages += 1
                offset += page.cards.count
                if !page.hasMore { break }
                try #require(!page.cards.isEmpty, "A page that promises more cards must advance its offset")
            }
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            #expect(seen.count == 5_000 && pages == 100)
            #expect(milliseconds <= 8_000, "Reading all 100 pages exceeded the conservative 8 s Release guardrail")
            samples.append([
                "kind": "complete_page_scan", "iteration": iteration, "elapsed_ms": milliseconds,
                "pages": pages, "unique_cards": seen.count, "page_limit": 50,
                "returned_title_body_utf8_bytes": returnedBytes,
                "physical_footprint_bytes": try workspacePhysicalFootprint(),
            ])
        }
        let report: [String: Any] = [
            "schema_version": 1, "measurement": "workspace_repository", "build_configuration": workspaceBuildConfiguration,
            "os_version": UIDevice.current.systemVersion,
            "simulator_model": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unavailable",
            "corpus_cards": 5_000, "seed_outside_timing": true, "page_limit": 50,
            "query_guardrail_ms": 750, "complete_scan_guardrail_ms": 8_000,
            "scope": "Wall time around awaited public repository queries; full scans include collecting IDs and byte counts. Neither user completion time nor frame hitches are measured.",
            "samples": samples,
        ]
        Attachment.record(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                          named: "workspace-repository-measurements.json")
    }

    @Test func largeLiteralPreviewSettlesAndReleasesEachRepeatedSession() async throws {
        try requireWorkspaceReleaseBuild()
        let fixture = try MeasurementWorkspace()
        defer { fixture.removeFiles() }
        let line = "原文のか\u{3099}・👩🏽‍💻 **記号も変えずに確認する**\r\n"
        let body = String(repeating: line, count: 200_000 / line.utf8.count)
        let draft = try await fixture.repository.beginDraft(title: "約 200 KB の原文", body: body)
        let card = try await fixture.repository.publish(draft)
        let host = try ViewTestHost()
        defer { host.close() }
        let delivery = MeasurementDeliverySink()
        var samples: [[String: Any]] = []
        var closedMemory: [Double] = []
        for iteration in 0..<7 {
            let mounted = try await mountMeasuredPreview(card: card, storage: fixture.repository, host: host, delivery: delivery)
            let visibleMemory = try workspacePhysicalFootprint()
            #expect(mounted.elapsedMilliseconds <= 6_000, "The mounted literal preview did not settle within its conservative 6 s guardrail")
            host.show(AnyView(EmptyView()))
            let closeStarted = ProcessInfo.processInfo.systemUptime
            try await host.wait { mounted.model.value == nil && mounted.scroll.value == nil }
            // Allow UIKit/SwiftUI's deferred releases to finish. Allocator caches
            // remain part of the footprint; this is not a claim of zero retention.
            try await Task.sleep(for: .milliseconds(100))
            let closed = try workspacePhysicalFootprint()
            let closeMilliseconds = (ProcessInfo.processInfo.systemUptime - closeStarted) * 1_000
            if iteration > 0 { closedMemory.append(closed) }
            samples.append([
                "iteration": iteration, "warmup": iteration == 0,
                "literal_utf8_bytes": body.utf8.count, "literal_utf16_units": body.utf16.count,
                "mount_to_two_equal_rendered_images_ms": mounted.elapsedMilliseconds,
                "close_to_release_and_100ms_quiescence_ms": closeMilliseconds,
                "rendered_png_bytes": mounted.renderedBytes,
                "visible_physical_footprint_bytes": visibleMemory,
                "closed_physical_footprint_bytes": closed,
                "session_and_scroll_released": mounted.model.value == nil && mounted.scroll.value == nil,
            ])
        }
        let minimum = try #require(closedMemory.min())
        let maximum = try #require(closedMemory.max())
        #expect(maximum - minimum <= 96 * 1_024 * 1_024, "Post-warmup closed footprints varied by more than the conservative 96 MiB guardrail")
        let report: [String: Any] = [
            "schema_version": 1, "measurement": "workspace_literal_preview", "build_configuration": workspaceBuildConfiguration,
            "os_version": UIDevice.current.systemVersion,
            "simulator_model": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unavailable",
            "host_width_points": Double(host.controller.view.bounds.width),
            "host_height_points": Double(host.controller.view.bounds.height), "capture_scale": 1,
            "literal_utf8_bytes": body.utf8.count, "mount_guardrail_ms": 6_000,
            "post_warmup_closed_footprint_range_bytes": maximum - minimum,
            "closed_footprint_range_guardrail_bytes": 96 * 1_024 * 1_024,
            "scope": "Actual WorkspaceUseView mounted in UIHostingController; layout is operationally settled when two rendered PNGs match at least 25 ms apart. Timing includes render, PNG encoding and polling. It is not user completion time, first visible frame latency, frame hitch data, or a comparison with the prior app.",
            "samples": samples,
        ]
        Attachment.record(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                          named: "workspace-preview-measurements.json")
    }
}

@MainActor
private struct MountedPreviewMeasurement {
    let elapsedMilliseconds: Double
    let renderedBytes: Int
    let model: WeakReference<UseSessionModel>
    let scroll: WeakReference<UIScrollView>
}

@MainActor
private func mountMeasuredPreview(card: TextCard, storage: WorkspaceRepository, host: ViewTestHost,
                                  delivery: MeasurementDeliverySink) async throws -> MountedPreviewMeasurement {
    let model = UseSessionModel(card: card, draft: nil, storage: storage)
    let started = ProcessInfo.processInfo.systemUptime
    host.show(AnyView(WorkspaceUseView(model: model, delivery: delivery, onFinished: {})))
    let image = try await settledWorkspaceImage(host: host)
    let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
    let scroll: UIScrollView = try #require(host.find(UIScrollView.self))
    return MountedPreviewMeasurement(elapsedMilliseconds: milliseconds, renderedBytes: image.count,
                                     model: WeakReference(model), scroll: WeakReference(scroll))
}

@MainActor
private func settledWorkspaceImage(host: ViewTestHost) async throws -> Data {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    var previous: Data?
    while ContinuousClock.now < deadline {
        host.controller.view.layoutIfNeeded()
        if host.find(UIScrollView.self) != nil && host.find(UINavigationBar.self) != nil {
            let view = try #require(host.controller.view)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
            var drewHierarchy = false
            let image = renderer.image { _ in drewHierarchy = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
            try #require(drewHierarchy, "The actual mounted preview hierarchy must render")
            let data = try #require(image.pngData())
            if previous == data { return data }
            previous = data
        }
        try await Task.sleep(for: .milliseconds(25))
    }
    throw PreviewMeasurementError.didNotSettle
}

private enum PreviewMeasurementError: Error {
    case didNotSettle
}

@MainActor
private final class MeasurementDeliverySink: TextDelivery {
    func copy(_ body: String) { Issue.record("A rendering measurement must not invoke the external copy effect") }
}

private var workspaceBuildConfiguration: String {
    #if DEBUG
    "Debug"
    #else
    "Release"
    #endif
}

private func requireWorkspaceReleaseBuild() throws {
    try #require(workspaceBuildConfiguration == "Release", "Run the dedicated NibblePerformance scheme in Release for these measurements")
}

private func workspacePhysicalFootprint() throws -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    try #require(result == KERN_SUCCESS, "Mach must return an actual physical-footprint observation")
    return Double(info.phys_footprint)
}

private struct MeasurementWorkspace: Sendable {
    let directory: URL
    let location: URL
    let repository: WorkspaceRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-measurement-\(UUID().uuidString)", isDirectory: true)
        location = directory.appendingPathComponent("workspace.sqlite")
        repository = try WorkspaceRepository(location: location)
    }

    /// Bulk seeding is setup, outside every timed interval. The public sample
    /// above verifies that both representations participate in the same corpus.
    func seedAdditionalCards(count: Int) throws {
        var candidate: OpaquePointer?
        let status = sqlite3_open_v2(location.path, &candidate, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let database = candidate else {
            sqlite3_close_v2(candidate)
            throw WorkspaceError.storage(code: status)
        }
        defer { sqlite3_close_v2(database) }
        try executeSetup("BEGIN IMMEDIATE", database: database)
        do {
            var prepared: OpaquePointer?
            let sql = "INSERT INTO cards(id,title,body,version,modified_at,pinned,deleted_at,origin_title,search_text,has_variables) VALUES(?,?,?,1,?,0,NULL,NULL,?,0)"
            let result = sqlite3_prepare_v2(database, sql, -1, &prepared, nil)
            guard result == SQLITE_OK, let statement = prepared else {
                sqlite3_finalize(prepared)
                throw WorkspaceError.storage(code: result)
            }
            defer { sqlite3_finalize(statement) }
            let timestamp = Date().timeIntervalSince1970
            for index in 0..<count {
                let title = "検証番号 \(index)"
                let suffix = index == 4_321 ? " %_\\唯一" : ""
                let body = "検証用の定型文 \(index) 東京都 ＡＢＣ カナ か\u{3099}\(suffix)"
                let normalized = (title + "\n" + body).precomposedStringWithCanonicalMapping
                    .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                try bindSetup(UUID().uuidString, position: 1, statement: statement)
                try bindSetup(title, position: 2, statement: statement)
                try bindSetup(body, position: 3, statement: statement)
                let dateStatus = sqlite3_bind_double(statement, 4, timestamp + Double(index) / 1_000)
                guard dateStatus == SQLITE_OK else { throw WorkspaceError.storage(code: dateStatus) }
                try bindSetup(normalized, position: 5, statement: statement)
                let step = sqlite3_step(statement)
                guard step == SQLITE_DONE else { throw WorkspaceError.storage(code: step) }
                let reset = sqlite3_reset(statement)
                guard reset == SQLITE_OK else { throw WorkspaceError.storage(code: reset) }
                let clear = sqlite3_clear_bindings(statement)
                guard clear == SQLITE_OK else { throw WorkspaceError.storage(code: clear) }
            }
            try executeSetup("COMMIT", database: database)
        } catch {
            let failure = error
            try executeSetup("ROLLBACK", database: database)
            throw failure
        }
    }

    func removeFiles() {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Could not remove performance fixture: \(error)") }
    }

    private func executeSetup(_ sql: String, database: OpaquePointer) throws {
        let status = sqlite3_exec(database, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw WorkspaceError.storage(code: status) }
    }

    private func bindSetup(_ value: String, position: Int32, statement: OpaquePointer) throws {
        let status = value.utf8CString.withUnsafeBufferPointer { buffer in
            sqlite3_bind_text(statement, position, buffer.baseAddress, Int32(buffer.count - 1),
                              unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard status == SQLITE_OK else { throw WorkspaceError.storage(code: status) }
    }
}
