@MainActor
protocol LibraryEffects {
    // Returning from copy commits the OS effect independently of the usage transaction.
    func copy(_ text: String)
    func announce(_ notice: LibraryModel.Notice)
}
