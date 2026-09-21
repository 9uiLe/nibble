import UIKit

/// Synchronous OS effects complete on MainActor before an operation reports success.
/// Storage and operation state belong to LibraryModel, not this adapter.
@MainActor
protocol LibraryEffects {
    func copy(_ text: String)
    func announce(_ text: String)
}

struct SystemLibraryEffects: LibraryEffects {
    func copy(_ text: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
    }

    func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
