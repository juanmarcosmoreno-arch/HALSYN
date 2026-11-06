import Foundation
import Testing
@testable import HalsynCore

@Suite("Carrera en la pantalla bloqueada")
struct RunLiveUpdateTests {
    @Test func timerStartSkipsPauses() {
        let sent = Date(timeIntervalSince1970: 10_000)
        let update = RunLiveUpdate(activity: .run, elapsed: 600, isPaused: false, distance: 2000, sent: sent)
        #expect(update.timerStart == Date(timeIntervalSince1970: 9_400))
    }

    @Test func paceStatusFollowsTheTarget() {
        var update = RunLiveUpdate(activity: .run, elapsed: 60, isPaused: false, distance: 200, pace: 300, paceFastest: 290, paceSlowest: 300)
        #expect(update.paceStatus == .onPace)
        update.pace = 320
        #expect(update.paceStatus == .slower)
        update.pace = 280
        #expect(update.paceStatus == .faster)
        update.paceFastest = nil
        #expect(update.paceStatus == nil)
    }

    @Test func roundTripsAsJSON() throws {
        let update = RunLiveUpdate(activity: .ride, elapsed: 12, isPaused: true, distance: 50, heartRate: 120, step: "SERIE 1/6", metric: false)
        let decoded = try JSONDecoder().decode(RunLiveUpdate.self, from: JSONEncoder().encode(update))
        #expect(decoded == update)
    }
}
