import SwiftUI

/// Supplies an ad for the library browsing surface when a provider is configured.
@MainActor
protocol AdvertisingContent {
    func libraryBanner() -> AnyView?
}

/// The app shows no ad container until a provider, consent flow, and policy URL exist.
struct UnconfiguredAdvertising: AdvertisingContent {
    func libraryBanner() -> AnyView? { nil }
}
