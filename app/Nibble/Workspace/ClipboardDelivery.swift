import UIKit
import UniformTypeIdentifiers

@MainActor
final class ClipboardDelivery: TextDelivery {
    func copy(_ body: String) {
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: Data(body.utf8)]], options: [.localOnly: true])
    }
}
