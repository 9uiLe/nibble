import Testing

// These suites share UIKit windows and OS effects, so they execute in one serial group.
@Suite("UI integration", .serialized)
struct UIIntegrationTests {}
