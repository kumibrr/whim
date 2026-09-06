public enum DeliveryReducer {
    public static func reduce(_ delivery: Delivery, event: DeliveryEvent) -> Delivery {
        var reduced = delivery

        switch event {
        case .configurationAvailabilityChanged(let isAvailable):
            reduced.hasUsableConfiguration = isAvailable
        case .connectivityChanged(let isConnected):
            reduced.isConnected = isConnected
        case .leaseChanged(let isHeld):
            reduced.hasExecutionLease = isHeld
        case .attemptStarted(let attempt):
            guard reduced.receipt == nil else { return reduced }
            guard !reduced.activeAttempts.contains(where: { $0.id == attempt.id }) else {
                return reduced
            }
            guard !reduced.failedAttempts.contains(where: { $0.attempt.id == attempt.id }) else {
                return reduced
            }
            reduced.activeAttempts.append(attempt)
        case .attemptFailed(let failure):
            guard reduced.receipt == nil else { return reduced }
            reduced.activeAttempts.removeAll { $0.id == failure.attempt.id }
            guard !reduced.failedAttempts.contains(where: { $0.attempt.id == failure.attempt.id }) else {
                return reduced
            }
            reduced.failedAttempts.append(failure)
        case .receipt(let receipt):
            guard reduced.receipt == nil else { return reduced }
            reduced.activeAttempts.removeAll { $0.id == receipt.attemptID }
            reduced.receipt = receipt
            reduced.workflowError = nil
        case .workflowFailed(let error):
            guard reduced.receipt == nil else { return reduced }
            reduced.workflowError = error
        }

        return reduced
    }
}
