public enum ComplicationWidgetKind: String, CaseIterable, Sendable {
    case recording = "app.whim.recording"
    case topLeft = "app.whim.recording.corner.topLeft"
    case bottomRight = "app.whim.recording.corner.bottomRight"
    case bottomLeft = "app.whim.recording.corner.bottomLeft"

    public static func reloadAll(using reload: (String) -> Void) {
        allCases.forEach { reload($0.rawValue) }
    }
}
