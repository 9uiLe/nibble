import Foundation

enum ShareError: Error, LocalizedError {
    case unsupported
    var errorDescription: String? { "文章またはURLを選んで共有してください。" }
}
