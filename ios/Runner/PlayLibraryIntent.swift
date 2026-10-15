import AppIntents

@available(iOS 16.0, *)
struct PlayLibraryIntent: AppIntent {
  static var title: LocalizedStringResource = "Shuffle Library"
  static var description = IntentDescription(
    "Shuffles the full Spotifin library, including the first song."
  )
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    DeepLinkStore.push("spotifin://play-library-shuffle")
    return .result()
  }
}

@available(iOS 16.0, *)
struct PlayLibraryInOrderIntent: AppIntent {
  static var title: LocalizedStringResource = "Play Library in Order"
  static var description = IntentDescription(
    "Plays the full Spotifin library in date-added order, newest first."
  )
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    DeepLinkStore.push("spotifin://play-library-in-order")
    return .result()
  }
}

@available(iOS 16.0, *)
struct SpotifinShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlayLibraryIntent(),
      phrases: [
        "Shuffle my library in \(.applicationName)",
        "Play my library shuffled in \(.applicationName)",
      ],
      shortTitle: "Shuffle Library",
      systemImageName: "shuffle"
    )
    AppShortcut(
      intent: PlayLibraryInOrderIntent(),
      phrases: [
        "Play my library in order in \(.applicationName)",
        "Play library in order in \(.applicationName)",
      ],
      shortTitle: "Play in Order",
      systemImageName: "list.number"
    )
  }
}
