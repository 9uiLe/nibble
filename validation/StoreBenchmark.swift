import Foundation
import Darwin

func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS)
    return info.phys_footprint
}
func millis(_ elapsed: Duration) -> Double {
    let value = elapsed.components
    return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
}
@main struct Benchmark {
    @MainActor static func main() async throws {
        let mode = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        let store = SnippetStore(location: url)
        if mode == "seed" {
            for number in 0..<10_000 {
                var draft = try await store.beginDraft()
                draft.title = "定型文 \(number)"
                draft.body = "  東京都の住所\nこんにちは。ご連絡ありがとうございます。 👩🏽‍💻  "
                let id = try await store.save(draft)
                if number % 200 == 0 { try await store.setPinned(true, id: id) }
            }
            let body = String(repeating: "長文の下書き\n", count: 6_250) // 118,750 UTF-8 bytes
            for number in 0..<200 {
                var draft = try await store.beginDraft(body: body)
                draft.title = "下書き \(number)"
                try await store.updateDraft(draft)
            }
            print("seeded")
            return
        }
        let clock = ContinuousClock()
        // Open the DB and initialize the same SQL/actor path before measuring.
        _ = try await store.search("東")
        let before = footprint()
        var values: [Double] = []
        var retained: UInt64 = 0
        for index in 0..<31 {
            let start = clock.now
            let page = try await store.library(LibraryRequest())
            let duration = millis(start.duration(to: clock.now))
            precondition(page.items.count == 100 && page.drafts.count == 3 && page.hasMore)
            if index == 0 { retained = withExtendedLifetime(page) { footprint() } }
            if index > 0 { values.append(duration) }
        }
        var searches: [[String: Any]] = []
        for (name, query, filter) in [("match", "東", LibraryFilter.all), ("miss", "見つからない語句", .all), ("pinned", "", .pinned)] {
            _ = try await store.search(query, filter: filter)
            var times: [Double] = []
            for _ in 0..<100 {
                let start = clock.now
                let items = try await store.search(query, filter: filter)
                times.append(millis(start.duration(to: clock.now)))
                precondition(items.count == (name == "miss" ? 0 : (name == "pinned" ? 50 : 100)))
            }
            searches.append(["query": name, "milliseconds": times])
        }
        let target = try await store.search()[0].id
        _ = try await store.editingDraft(for: target)
        var resumeTimes: [Double] = []
        for _ in 0..<100 {
            let start = clock.now
            _ = try await store.editingDraft(for: target)
            resumeTimes.append(millis(start.duration(to: clock.now)))
        }
        var draft = try await store.beginDraft(body: "write")
        var writeTimes: [Double] = []
        for index in 0..<100 {
            draft.body = "write \(index)"
            let start = clock.now
            try await store.updateDraft(draft)
            writeTimes.append(millis(start.duration(to: clock.now)))
        }
        try await store.discardDraft(draft)
        let longText = String(repeating: "a", count: 999_999)
        let options = [longText + "x", longText + "y"]
        let editor = EditorModel(draft: Draft(id: UUID(), snippetID: nil, baseRevision: 0, title: "long", body: options[1], sequence: 0), store: store)
        var inputTimes: [Double] = []
        for index in 0..<100 {
            let start = clock.now
            editor.body = options[index % 2]
            precondition(editor.canSave)
            inputTimes.append(millis(start.duration(to: clock.now)))
        }
        precondition(editor.body == options[1] && editor.draft.sequence == 100)
        let result: [String: Any] = ["resume_milliseconds": resumeTimes, "write_milliseconds": writeTimes, "input_setter_and_can_save_milliseconds": inputTimes, "list_milliseconds": values, "footprint_before": before,
            "footprint_first_list_retained": retained, "searches": searches,
            "snippets": 10_000, "drafts": 200, "draft_body_utf8_bytes": String(repeating: "長文の下書き\n", count: 6_250).utf8.count]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
