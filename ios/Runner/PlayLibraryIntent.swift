import AppIntents

@available(iOS 16.0, *)
struct PlayLibraryIntent: AppIntent {
  static var title: LocalizedStringResource = "Play Library"
  static var description = IntentDescription(
    "Plays the most recent song and queues the full library in Spotifin."
  )
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    // The shortcut already launches the app. Pass the request directly to the
    // Flutter bridge instead of reopening the app through its URL scheme.
    DeepLinkStore.push("spotifin://play-library")
    return .result()
  }
}

@available(iOS 16.0, *)
struct SpotifinShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlayLibraryIntent(),
      phrases: [
        "Play my library in \(.applicationName)",
        "Play library in \(.applicationName)",
      ],
      shortTitle: "Play Library",
      systemImageName: "music.note.list"
    )
  }
}
