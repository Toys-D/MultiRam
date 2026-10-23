import AppIntents

struct Delete: AppIntent, CustomIntentMigratedAppIntent {
  static let intentClassName = "DeleteIntent"

  static var title: LocalizedStringResource = "Delete Item from Clipboard History"
  static var description = IntentDescription("Deletes an item from MultiRam clipboard history.")

  @Parameter(title: "Number", default: 1)
  var number: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Delete \(\.$number) Item from Clipboard History")
  }

  private let positionOffset = 1

  @MainActor
  func perform() async throws -> some IntentResult {
    let items = AppState.shared.history.items
    guard number > 0, number <= items.count else {
      throw AppIntentError.notFound
    }
    let index = number - positionOffset

    guard AppState.shared.history.delete(items[index]) else {
      throw AppIntentError.storageFailure
    }

    return .result()
  }
}
