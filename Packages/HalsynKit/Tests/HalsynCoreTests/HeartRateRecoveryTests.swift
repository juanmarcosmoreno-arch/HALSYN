import Foundation
import Testing
@testable import HalsynCore

@Suite("Recuperación del pulso")
struct HeartRateRecoveryTests {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func endHeartRateIsThePeakOfTheLastSeconds() {
        let readings: [(date: Date, bpm: Double)] = [
            (end.addingTimeInterval(-40), 176), // fuera de la ventana de 20 s
            (end.addingTimeInterval(-15), 168),
            (end.addingTimeInterval(-5), 171),
            (end.addingTimeInterval(-1), 169),
            (end.addingTimeInterval(2), 175), // después de terminar: no cuenta
        ]
        #expect(HeartRateRecovery.endHeartRate(readings, end: end) == 171)
        #expect(HeartRateRecovery.endHeartRate([], end: end) == nil)
    }

    @Test func dropsAtOneAndTwoMinutes() throws {
        // Cada 5 s, bajando 0,5 lpm por segundo el primer minuto y 0,25 después.
        let samples = stride(from: 0.0, through: 125, by: 5).map { second -> RecoverySample in
            let bpm = second <= 60 ? 170 - 0.5 * second : 140 - 0.25 * (second - 60)
            return RecoverySample(elapsed: second, bpm: bpm)
        }
        let result = HeartRateRecovery.result(date: end, endHeartRate: 170, samples: samples)
        #expect(result.oneMinute == 30)
        #expect(result.twoMinutes == 45)
        #expect(result.fiveMinutes == nil)
        // Interpolación entre lecturas separadas.
        #expect(HeartRateRecovery.heartRate(at: 62, in: [RecoverySample(elapsed: 58, bpm: 150), RecoverySample(elapsed: 66, bpm: 142)]) == 146)
        // Sin lecturas cerca del minuto, no hay valor (no se inventa).
        #expect(HeartRateRecovery.heartRate(at: 60, in: [RecoverySample(elapsed: 20, bpm: 150), RecoverySample(elapsed: 100, bpm: 130)]) == nil)
    }

    @Test func trendComparesRecentAndPreviousMeasurements() throws {
        let readings = (0..<10).map { index in
            RecoveryReading(date: end.addingTimeInterval(Double(index) * 86_400), oneMinute: index < 5 ? 22 : 28, twoMinutes: nil, endHeartRate: nil, origin: .demo)
        }
        let trend = try #require(RecoveryTrend.make(readings))
        #expect(trend.recentAverage == 28 && trend.previousAverage == 22 && trend.change == 6)
        #expect(RecoveryTrend.make(Array(readings.prefix(9))) == nil)
    }

    @Test func trendOnlyComparesSimilarEndings() throws {
        // Las 5 de 150 lpm al terminar no se comparan con una última de 175.
        var readings = (0..<10).map { index in
            RecoveryReading(date: end.addingTimeInterval(Double(index) * 86_400), oneMinute: index < 5 ? 22 : 30, twoMinutes: nil, endHeartRate: index < 5 ? 172 : 150, origin: .demo)
        }
        #expect(RecoveryTrend.make(readings) == nil)
        readings = readings.map { RecoveryReading(date: $0.date, oneMinute: $0.oneMinute, twoMinutes: nil, endHeartRate: 170, origin: .demo) }
        let trend = try #require(RecoveryTrend.make(readings))
        #expect(trend.isMeaningful)
        // Diferencias dentro del ruido no cuentan como cambio.
        #expect(!RecoveryTrend(recentAverage: 31, previousAverage: 29, count: 5).isMeaningful)
    }

    @Test func resultsBecomeReadingsOnlyWithTheFirstMinute() {
        let complete = HeartRateRecoveryResult(date: end, endHeartRate: 170, oneMinute: 28, twoMinutes: 44, fiveMinutes: nil, samples: [])
        #expect(RecoveryReading(complete)?.twoMinutes == 44)
        let short = HeartRateRecoveryResult(date: end, endHeartRate: 170, oneMinute: nil, twoMinutes: nil, fiveMinutes: nil, samples: [])
        #expect(RecoveryReading(short) == nil)
    }

    @Test func settingsDefaults() {
        var settings = RunSettings()
        #expect(settings.offersRecovery && settings.recoveryDuration == 2)
        settings.recoveryMinutes = 7
        #expect(settings.recoveryDuration == 2)
        settings.recoveryDuration = 5
        settings.offersRecovery = false
        #expect(settings.recoveryDuration == 5 && !settings.offersRecovery)
    }

    @Test func demoRecoveriesAreLabelledAndImprove() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let provider = DemoHealthDataProvider(calendar: calendar, now: { Date(timeIntervalSince1970: 1_793_000_000) })
        let readings = await provider.heartRateRecoveries(days: 120)
        #expect(readings.count >= 10)
        #expect(readings.allSatisfy { $0.origin.isDemo })
        let trend = try #require(RecoveryTrend.make(readings))
        #expect(trend.change > 0)
    }
}
