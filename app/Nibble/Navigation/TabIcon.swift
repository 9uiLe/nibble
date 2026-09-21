import SwiftUI
import UIKit

/// Template artwork has its own size; TabView owns the glass, selection and hit area.
@MainActor
enum TabIcon {
    static let library = image("list.bullet")
    static let settings = image("gearshape")
    static let search = image("magnifyingglass")

    private static func image(_ name: String) -> Image {
        let size = CGSize(width: 20, height: 20)
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else {
            preconditionFailure("Missing tab symbol: \(name)")
        }
        let scale = min(size.width / symbol.size.width, size.height / symbol.size.height)
        let drawnSize = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let bounds = CGRect(x: (size.width - drawnSize.width) / 2,
                            y: (size.height - drawnSize.height) / 2,
                            width: drawnSize.width, height: drawnSize.height)
        let artwork = UIGraphicsImageRenderer(size: size).image { _ in symbol.draw(in: bounds) }
        return Image(uiImage: artwork.withRenderingMode(.alwaysTemplate))
    }
}
