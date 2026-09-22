import UIKit

struct SystemLibraryEffects: LibraryEffects {
    func copy(_ text: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
    }

    func announce(_ notice: LibraryModel.Notice) {
        UIAccessibility.post(notification: .announcement, argument: notice.announcement)
    }
}
