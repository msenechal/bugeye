import Foundation
import RecordingCore
import Testing

@Suite struct TakeRecoveryTests {
    let a = UUID()
    let b = UUID()
    let c = UUID()

    private func file(_ uuid: UUID, _ suffix: String, _ seconds: Double = 0) -> TakeRecovery.File {
        TakeRecovery.File(
            name: "Take-" + uuid.uuidString.lowercased() + suffix, created: Date(timeIntervalSince1970: seconds))
    }

    @Test func aLeftoverMovieIsRecoveredWithItsTimeline() {
        let files = [
            file(a, ".mov", 100), file(a, ".timeline.jsonl", 90), file(b, ".mov", 200), file(c, ".timeline.jsonl"),
            TakeRecovery.File(name: ".DS_Store", created: Date()),
        ]
        let plan = TakeRecovery.plan(files: files, liveTakes: [b])
        #expect(
            plan.recover == [
                TakeRecovery.Recovery(
                    take: a, movie: "Take-\(a.uuidString.lowercased()).mov",
                    timeline: "Take-\(a.uuidString.lowercased()).timeline.jsonl",
                    createdAt: Date(timeIntervalSince1970: 90))
            ])
        // A timeline with no movie is left alone (its recording may have been delivered).
        #expect(plan.delete.isEmpty)
    }

    @Test func aTakeWithoutATimelineIsStillRecovered() {
        let plan = TakeRecovery.plan(files: [file(a, ".mov", 5)], liveTakes: [])
        #expect(plan.recover.map(\.timeline) == [nil])
    }

    @Test func liveTakesAndOtherFilesAreLeftAlone() {
        let files = [
            file(a, ".mov"), file(a, ".timeline.jsonl"), TakeRecovery.File(name: "Take-nope.mov", created: Date()),
        ]
        let plan = TakeRecovery.plan(files: files, liveTakes: [a])
        #expect(plan.recover.isEmpty)
        #expect(plan.delete.isEmpty)
    }

    @Test func aConvertedMovieIsRecoveredAndAPartialConversionDeleted() {
        let files = [file(a, ".mp4", 7), file(b, ".mov", 8), file(b, ".mp4", 9)]
        let plan = TakeRecovery.plan(files: files, liveTakes: [])
        #expect(
            plan.recover.map(\.movie) == [
                "Take-\(a.uuidString.lowercased()).mp4", "Take-\(b.uuidString.lowercased()).mov",
            ])
        #expect(plan.delete == ["Take-\(b.uuidString.lowercased()).mp4"])
    }

    @Test func takeFileNames() {
        #expect(TakeRecovery.movieName(take: a) == "Take-\(a.uuidString.lowercased()).mov")
        #expect(TakeRecovery.take(fromMovieName: "Take-\(a.uuidString.lowercased()).mov") == a)
        #expect(TakeRecovery.take(fromMovieName: "Take-x.mov") == nil)
    }
}
