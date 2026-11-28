/// Asked when the user quits (⌘Q, Quit Bugeye in either menu). One gate, two stages (K11).
@MainActor
public final class TerminationGate {
    private var asks: [@MainActor () async -> Bool] = []
    private var finishes: [@MainActor () async -> Void] = []
    private var running: Task<Bool, Never>?

    public init() {}

    /// May cancel (an editor's unsaved-changes prompt). Asked first, in registration order; the first false
    /// cancels the quit, and later participants aren't asked.
    public func addAsk(_ participant: @escaping @MainActor () async -> Bool) {
        asks.append(participant)
    }

    /// Can't cancel; finishes work first (a recording stops and delivers). Run after every ask said yes,
    /// in registration order, each awaited.
    public func addFinish(_ participant: @escaping @MainActor () async -> Void) {
        finishes.append(participant)
    }

    /// A second call while one is running returns that call's answer.
    public func shouldTerminate() async -> Bool {
        if let running { return await running.value }
        let task = Task { @MainActor [asks, finishes] in
            for ask in asks {
                guard await ask() else { return false }
            }
            for finish in finishes { await finish() }
            return true
        }
        running = task
        let answer = await task.value
        running = nil
        return answer
    }
}
