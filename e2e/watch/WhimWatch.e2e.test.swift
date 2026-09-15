import Foundation

/// Installed-app tests isolate storage and use deterministic, playable audio at the
/// microphone boundary. The runner owns and removes the fixture after the suite.
enum WatchUITestConfiguration {
    static var arguments: [String] {
        var result = ["-WhimWatchTestID", UUID().uuidString]
        if let audio = ProcessInfo.processInfo.environment["WHIM_WATCH_FIXTURE_AUDIO"] {
            result += ["-WhimFixtureAudio", audio]
        }
        return result
    }
}
