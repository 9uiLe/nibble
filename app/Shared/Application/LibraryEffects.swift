/// OS effects complete on MainActor before the use case reports success.
@MainActor
protocol LibraryEffects {
    func copy(_ text: String)
    func announce(_ notice: LibraryModel.Notice)
}
