import Foundation
import Darwin
import RiveRuntime
import SwiftUI
import UIKit
import Testing
@testable import Nibble

@Suite("Rive playback performance", .serialized)
struct RivePlaybackMeasurements {
    /// The logger observes the real runtime clock; it never advances a machine itself.
    /// Keep these samples separate from presented-frame latency and hitch measurements.
    @Test @MainActor
    func rivePlaybackMeasurements() async throws {
        let log = RivePlaybackLog()
        let previous = RiveLog.logger
        RiveLog.logger = log
        defer { RiveLog.logger = previous }
        let host = try ViewTestHost()
        defer { host.close() }
        var samples: [[String: Double]] = []
        for keyboard in [false, true] {
            for iteration in 0..<6 {
                log.reset()
                let start = ProcessInfo.processInfo.systemUptime
                host.show(keyboard ? AnyView(KeyboardGuideView()) : AnyView(AboutView()))
                try await host.wait { !log.advances.isEmpty }
                weak var native = host.find(RiveUIView.self)
                weak var rive = native?.rive
                weak var file = rive?.file
                let firstAdvance = try #require(log.advances.first)
                try await Task.sleep(for: .milliseconds(350))
                let displayedMemory = try riveFootprint()
                let created = log.count("Initializing view")
                let scroll = try #require(host.find(UIScrollView.self))
                scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
                try await host.wait { native?.isPaused == true }
                try await Task.sleep(for: .milliseconds(150))
                let stopped = log.advances.count
                try await Task.sleep(for: .milliseconds(300))
                #expect(log.advances.count == stopped)
                let resumedAt = ProcessInfo.processInfo.systemUptime
                scroll.setContentOffset(.zero, animated: false)
                try await host.wait { log.advances.count > stopped }
                let resumed = log.advances[stopped]
                #expect(resumed.delta == 0)
                #expect(host.find(RiveUIView.self) === native)
                #expect(log.count("Initializing view") == created)
                host.show(AnyView(EmptyView()))
                try await host.wait { native == nil && rive == nil && file == nil }
                try await Task.sleep(for: .milliseconds(100))
                let closedMemory = try riveFootprint()
                #expect((firstAdvance.time - start) * 1000 <= (iteration == 0 ? 200 : 100))
                #expect((resumed.time - resumedAt) * 1000 <= 100)
                #expect(created == 1)
                    samples.append([
                        "keyboard": keyboard ? 1 : 0,
                        "iteration": Double(iteration),
                        "displayed_footprint_bytes": displayedMemory,
                        "closed_footprint_bytes": closedMemory,
                        "mount_to_first_advance_ms": (firstAdvance.time - start) * 1000,
                        "visibility_request_to_resume_advance_ms": (resumed.time - resumedAt) * 1000,
                        "native_views_created": Double(created),
                        "files_created": Double(log.count("Initializing file")),
                        "workers_created": Double(log.count("Initializing worker"))
                    ])
            }
        }
        for keyboard in [0.0, 1.0] {
            let memory = samples.filter { $0["keyboard"] == keyboard && $0["iteration"] != 0 }
                .compactMap { $0["closed_footprint_bytes"] }
            #expect(try #require(memory.max()) - #require(memory.min()) <= 8 * 1024 * 1024)
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        Attachment.record(data, named: "rive-playback-measurements.json")
    }

}

private func riveFootprint() throws -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    try #require(result == KERN_SUCCESS)
    return Double(info.phys_footprint)
}
