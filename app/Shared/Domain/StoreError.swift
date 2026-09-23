import Foundation

enum StoreError: Error, Equatable {
    case unavailable, database, newerVersion, conflict, staleDraft, missing, empty, tooLarge, freeLimit
}
