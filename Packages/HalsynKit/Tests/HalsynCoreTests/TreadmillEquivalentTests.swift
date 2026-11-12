import Foundation
import Testing
@testable import HalsynCore

@Suite("Equivalencia en cinta")
struct TreadmillEquivalentTests {
    @Test func onePercentMatchesOutdoorPace() {
        // 6:00 min/km = 10,0 km/h; con 1 % es la misma velocidad (Jones & Doust).
        #expect(TreadmillEquivalent.speed(outdoorPace: 360) == 10.0)
        // 5:00 min/km = 12,0 km/h.
        #expect(TreadmillEquivalent.speed(outdoorPace: 300) == 12.0)
    }

    @Test func moreInclineMeansLessSpeed() {
        let one = TreadmillEquivalent.speed(outdoorPace: 360, incline: 0.01)
        let two = TreadmillEquivalent.speed(outdoorPace: 360, incline: 0.02)
        let three = TreadmillEquivalent.speed(outdoorPace: 360, incline: 0.03)
        // ACSM: 10 × 0,2 / (0,2 + 0,009) = 9,57 → 9,6; con 3 %: 10 × 0,2 / 0,218 = 9,17 → 9,2.
        #expect(two == 9.6)
        #expect(three == 9.2)
        #expect(one > two && two > three)
    }

    @Test func intervalSessionGuide() {
        let session = PlannedSession(date: .now, kind: .intervals, distance: 8000, repeats: 5, repeatDistance: 800, pace: PaceRange(fastest: 270, slowest: 280))
        let steps = TreadmillEquivalent.guide(for: session, easyPace: PaceRange(fastest: 345, slowest: 375))
        #expect(steps.map(\.kind) == [.warmup, .work, .recovery, .cooldown])
        let work = steps[1]
        #expect(work.repeats == 5)
        // 4:30–4:40 min/km → 12,9–13,3 km/h.
        #expect(work.speed == 12.9...13.3)
        #expect(steps[2].repeats == 4)
        #expect(steps[2].duration == 120)
        let warmup = steps[0]
        #expect(warmup.speed == 9.6...10.4)
        #expect(abs((warmup.duration ?? 0) - 720) < 1)
    }

    @Test func easyRunAndRest() {
        let easy = PlannedSession(date: .now, kind: .easy, distance: 6000, pace: PaceRange(fastest: 346, slowest: 356))
        let steps = TreadmillEquivalent.guide(for: easy, easyPace: nil, incline: 0.02)
        #expect(steps.count == 1)
        #expect(steps[0].kind == .steady)
        #expect(steps[0].incline == 0.02)
        #expect(TreadmillEquivalent.guide(for: PlannedSession(date: .now, kind: .rest, distance: 0), easyPace: nil).isEmpty)
    }
}
