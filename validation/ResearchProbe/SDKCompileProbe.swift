// Compile probes only. They do not prove discovery, permissions, delivery or host behavior.
import AppIntents
import WidgetKit
import SwiftUI
import UIKit
import MetricKit
import CloudKit
import SwiftData
import Observation

struct ProbeOpenIntent: AppIntent {
    static var title: LocalizedStringResource { "研究用一覧を開く" }
    static var supportedModes: IntentModes { .foreground }
    func perform() async throws -> some IntentResult { .result() }
}

struct ProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ProbeOpenIntent(), phrases: ["Open \(.applicationName)"], shortTitle: "研究用一覧", systemImageName: "text.page")
    }
}

struct ProbeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.nibble.probe.open") {
            ControlWidgetButton(action: ProbeOpenIntent()) { Label("研究用一覧", systemImage: "text.page") }
        }
        .displayName("研究用一覧")
    }
}

struct ProbeEntry: TimelineEntry { let date: Date }
struct ProbeTimeline: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry { ProbeEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) { completion(ProbeEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        completion(Timeline(entries: [ProbeEntry(date: .now)], policy: .never))
    }
}
struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.nibble.probe.widget", provider: ProbeTimeline()) { _ in
            Button(intent: ProbeOpenIntent()) { Text("研究用一覧") }
                .widgetURL(URL(string: "nibble-probe://list"))
                .containerBackground(.background, for: .widget)
        }
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

@Observable final class ProbeObservation { var query = "" }
@ModelActor actor ProbeModelActor {}

@MainActor func probeExtensionAPIs(_ keyboard: UIInputViewController, _ context: NSExtensionContext) {
    ProbeShortcuts.updateAppShortcutParameters()
    keyboard.textDocumentProxy.insertText("dummy")
    keyboard.textDocumentProxy.deleteBackward()
    keyboard.advanceToNextInputMode()
    _ = keyboard.hasFullAccess
    _ = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.nibble.probe")
    context.completeRequest(returningItems: [NSExtensionItem()])
    context.cancelRequest(withError: CocoaError(.userCancelled))
    UIPasteboard.general.setItems([["public.utf8-plain-text": "dummy"]], options: [.localOnly: true, .expirationDate: Date()])
    WidgetCenter.shared.reloadAllTimelines()
    ControlCenter.shared.reloadAllControls()
}

final class ProbeMetrics: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {}
    func didReceive(_ payloads: [MXDiagnosticPayload]) {}
    func register() { MXMetricManager.shared.add(self) }
}

func probeCloud(_ engine: CKSyncEngine) async throws {
    try await engine.fetchChanges()
    try await engine.sendChanges()
}

func probeCloudState(_ event: CKSyncEngine.Event.StateUpdate) throws -> Data {
    try JSONEncoder().encode(event.stateSerialization)
}
