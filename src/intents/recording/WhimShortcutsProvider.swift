import AppIntents

struct WhimShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordWhimIntent(), phrases: ["Record a Whim in \(.applicationName)"],
            shortTitle: "Record a Whim", systemImageName: "mic.fill")
        AppShortcut(intent: StopWhimRecordingIntent(), phrases: ["Stop Whim Recording in \(.applicationName)"],
            shortTitle: "Stop Whim Recording", systemImageName: "stop.fill")
    }
}
