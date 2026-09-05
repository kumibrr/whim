import Foundation

public enum RetryClassification: Codable, Equatable, Sendable {
    case retryable
    case permanent
}

public enum RetryPolicy {
    public static let maximumFailedAttempts = 3
    public static let delays: [TimeInterval] = [0, 60, 900]

    public static func classification(for failure: AttemptFailureReason) -> RetryClassification {
        switch failure {
        case .network:
            return .retryable
        case .httpStatus(let statusCode)
            where statusCode == 408 ||
            statusCode == 425 ||
            statusCode == 429 ||
            (500...599).contains(statusCode):
            return .retryable
        case .httpStatus:
            return .permanent
        }
    }

    public static func nextEligibility(
        after failures: Int,
        now: Date,
        retryAfter: Date?
    ) -> Date? {
        guard failures >= 0, failures < maximumFailedAttempts else { return nil }
        let policyDate = now.addingTimeInterval(delays[failures])
        return max(policyDate, retryAfter ?? policyDate)
    }
}
