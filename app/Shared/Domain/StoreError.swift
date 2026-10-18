enum StoreError: Error, Equatable {
    case unavailable
    case database
    case newerVersion
    case conflict
    case staleDraft
    case missing
    case empty
    case tooLarge
}
