public enum RetentionPolicy: Int, Codable, CaseIterable, Sendable {
    case immediately = 0
    case oneDay = 1
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90
    case never = -1
}
