import Foundation

public enum DeliveryTimeouts {
    public static let request: TimeInterval = 15
    public static let resource: TimeInterval = 120
    public static let lease: TimeInterval = resource + 15
    public static let maximumErrorExcerptBytes = 4 * 1_024
}
