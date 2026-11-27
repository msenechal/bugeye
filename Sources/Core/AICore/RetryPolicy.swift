import Foundation

/// When to retry a Messages call (`design/13` §5, `claude-api` skill): 429, 5xx (529 included) and
/// connection errors, with exponential backoff or the server's `retry-after`. Never other 4xx.
public struct RetryPolicy: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        /// An HTTP answer. `retryAfter` and `shouldRetry` are the raw header values; `errorCode` is
        /// `error.details.error_code` from the body.
        case status(Int, retryAfter: String?, shouldRetry: String?, errorCode: String?)
        /// No HTTP answer at all.
        case connectionFailed
    }

    public var maxRetries: Int
    public var baseDelay: Duration
    public var maxDelay: Duration
    /// A `retry-after` longer than this means "not now": give up instead of blocking the feature.
    public var maxRetryAfter: Duration

    public init(
        maxRetries: Int = 2, baseDelay: Duration = .milliseconds(500), maxDelay: Duration = .seconds(8),
        maxRetryAfter: Duration = .seconds(60)
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxRetryAfter = maxRetryAfter
    }

    /// How long to wait before the next attempt, or nil to stop. `retriesSoFar` starts at 0.
    public func delay(after outcome: Outcome, retriesSoFar: Int) -> Duration? {
        guard retriesSoFar < maxRetries else { return nil }
        switch outcome {
        case .connectionFailed:
            return backoff(retriesSoFar)
        case .status(let status, let retryAfter, let shouldRetry, let errorCode):
            guard status == 429 || (500...599).contains(status) else { return nil }
            if shouldRetry?.lowercased() == "false" { return nil }
            // A monthly spend cap answers 429 with no retry-after; retrying can't help.
            if status == 429, errorCode == "enforced_spend_limit_reached" { return nil }
            if let retryAfter, let seconds = Double(retryAfter.trimmingCharacters(in: .whitespaces)), seconds >= 0 {
                // Compare before converting: a huge or infinite header ("1e300", "inf") would trap in Int64(_:).
                let maxSeconds =
                    Double(maxRetryAfter.components.seconds)
                    + Double(maxRetryAfter.components.attoseconds) / 1e18
                guard seconds.isFinite, seconds <= maxSeconds else { return nil }
                return .milliseconds(Int64((seconds * 1000).rounded(.up)))
            }
            return backoff(retriesSoFar)
        }
    }

    private func backoff(_ retriesSoFar: Int) -> Duration {
        let delay = baseDelay * (1 << min(retriesSoFar, 16))
        return min(delay, maxDelay)
    }
}
