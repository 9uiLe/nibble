import Testing

/// Pasteboard, announcements and mounted windows are process-global test resources.
@Suite("UI integration", .serialized)
struct UIIntegrationTests {}
