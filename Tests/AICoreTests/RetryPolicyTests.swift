import AICore
import Testing

@Suite struct RetryPolicyTests {
    let policy = RetryPolicy()

    func status(_ code: Int, retryAfter: String? = nil, shouldRetry: String? = nil, errorCode: String? = nil)
        -> RetryPolicy.Outcome
    {
        .status(code, retryAfter: retryAfter, shouldRetry: shouldRetry, errorCode: errorCode)
    }

    @Test(arguments: [429, 500, 502, 503, 529])
    func retryableStatusesBackOffExponentially(code: Int) {
        #expect(policy.delay(after: status(code), retriesSoFar: 0) == .milliseconds(500))
        #expect(policy.delay(after: status(code), retriesSoFar: 1) == .seconds(1))
        #expect(policy.delay(after: status(code), retriesSoFar: 2) == nil)
    }

    @Test(arguments: [400, 401, 402, 403, 404, 408, 409, 413, 422])
    func otherClientErrorsAreNeverRetried(code: Int) {
        #expect(policy.delay(after: status(code), retriesSoFar: 0) == nil)
    }

    @Test func connectionFailuresAreRetried() {
        #expect(policy.delay(after: .connectionFailed, retriesSoFar: 0) == .milliseconds(500))
        #expect(policy.delay(after: .connectionFailed, retriesSoFar: 2) == nil)
    }

    @Test func retryAfterWins() {
        #expect(policy.delay(after: status(429, retryAfter: "3"), retriesSoFar: 0) == .seconds(3))
        #expect(policy.delay(after: status(529, retryAfter: " 0.25 "), retriesSoFar: 1) == .milliseconds(250))
    }

    @Test func aLongRetryAfterMeansGiveUp() {
        #expect(policy.delay(after: status(429, retryAfter: "61"), retriesSoFar: 0) == nil)
    }

    @Test(arguments: ["1e300", "inf", "infinity", "9223372036854775807"])
    func anEnormousRetryAfterMeansGiveUpWithoutCrashing(header: String) {
        #expect(policy.delay(after: status(429, retryAfter: header), retriesSoFar: 0) == nil)
    }

    @Test func anUnreadableRetryAfterFallsBackToBackoff() {
        #expect(
            policy.delay(after: status(503, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT"), retriesSoFar: 0)
                == .milliseconds(500))
        #expect(policy.delay(after: status(503, retryAfter: "-1"), retriesSoFar: 0) == .milliseconds(500))
    }

    @Test func theServerCanSayDoNotRetry() {
        #expect(policy.delay(after: status(500, shouldRetry: "false"), retriesSoFar: 0) == nil)
        #expect(policy.delay(after: status(500, shouldRetry: "true"), retriesSoFar: 0) == .milliseconds(500))
    }

    @Test func aSpendCapIsNotRetried() {
        #expect(policy.delay(after: status(429, errorCode: "enforced_spend_limit_reached"), retriesSoFar: 0) == nil)
    }

    @Test func backoffIsCapped() {
        let patient = RetryPolicy(maxRetries: 10)
        #expect(patient.delay(after: .connectionFailed, retriesSoFar: 9) == .seconds(8))
    }
}
