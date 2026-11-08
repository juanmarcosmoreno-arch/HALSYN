import Foundation
import Testing
@testable import HalsynCore

@Suite("Evolución · Fase 1: FC máxima, intensidad y sueño")
struct EvolutionPhase1Tests {
    private let calendar = NovemberFixture.calendar

    private func run(_ day: Int, month: Int = 10, max: Double, average: Double = 160, indoor: Bool = false) -> WorkoutSummary {
        let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 18))!
        return WorkoutSummary(activity: indoor ? .indoorRun : .outdoorRun, start: start, duration: 1800, distanceMeters: 5000, averageHeartRate: average, maxHeartRate: max, activeEnergyKilocalories: nil, averageCadence: 160, origin: .demo)
    }

    // MARK: FC máxima

    @Test func realCaseValidatesTheRepeatedPeak() {
        let assessment = MaxHeartRateValidator.assess(runs: NovemberFixture.runs, today: NovemberFixture.today, calendar: calendar)
        #expect(assessment.recorded == 189)
        // 189 (cinta, 23/6) aparece una sola vez; 186 se repite (27/8 y 1/9).
        #expect(assessment.validated == 186)
        #expect(!assessment.isProvisional)
        #expect(assessment.peaks.first { $0.reported == 189 }?.status == .isolated)
        #expect(assessment.supporting.count >= 2)
        // La cinta no se excluye: los dos 186 son en cinta.
        #expect(assessment.supporting.contains { $0.isIndoor })
    }

    @Test func isolatedSpikeIsNotTheMax() {
        let runs = [run(1, max: 205), run(3, max: 181), run(5, max: 180), run(8, max: 176)]
        let assessment = MaxHeartRateValidator.assess(runs: runs, today: NovemberFixture.today, calendar: calendar)
        #expect(assessment.validated == 181)
        #expect(assessment.peaks.first { $0.reported == 205 }?.status == .isolated)
    }

    @Test func transientPeakInSamplesIsAnArtifact() {
        let spiky = run(2, max: 199, average: 165)
        // Muestras cada 5 s alrededor de 175 con un único valor a 199.
        var points: [HeartRatePoint] = (0..<120).map { HeartRatePoint(date: spiky.start.addingTimeInterval(Double($0) * 5), bpm: 170 + Double($0 % 6)) }
        points[60] = HeartRatePoint(date: points[60].date, bpm: 199)
        let assessment = MaxHeartRateValidator.assess(runs: [spiky, run(4, max: 176), run(6, max: 175)], samples: [spiky.id: points], today: NovemberFixture.today, calendar: calendar)
        let peak = assessment.peaks.first { $0.id == spiky.id }
        #expect(peak?.status == .transient)
        #expect((peak?.sustained ?? 0) < 180)
        #expect(assessment.validated == 176)
    }

    @Test func contradictoryRecordsWithoutRepetitionAreProvisional() {
        let assessment = MaxHeartRateValidator.assess(runs: [run(2, max: 184)], today: NovemberFixture.today, calendar: calendar)
        #expect(assessment.validated == 184)
        #expect(assessment.isProvisional)
        let gap = MaxHeartRateValidator.assess(runs: [run(2, max: 215, average: 140), run(4, max: 182), run(6, max: 182)], today: NovemberFixture.today, calendar: calendar)
        #expect(gap.peaks.first { $0.reported == 215 }?.status == .implausibleGap)
        #expect(gap.validated == 182)
    }

    @Test func configuredValueIsKeptWhenSourceChanges() {
        var zones = HeartRateZoneConfiguration(maxSource: .manual, maxHeartRate: 182)
        #expect(zones.configuredMax == 182)
        zones.configuredMaxHeartRate = 182
        zones.maxSource = .validated
        zones.maxHeartRate = 186
        #expect(zones.configuredMax == 182)
    }

    // MARK: Intensidad

    @Test func evidenceHierarchy() {
        let run7 = NovemberFixture.run(11, 7, 9)
        // Umbral validado (Friel): 166 / 172 = 96,5 % → tempo.
        #expect(IntensityClassifier.classify(run7, maxHeartRate: 186, lactateThreshold: 172).kind == .tempo)
        // Zonas personales por reserva: (166 − 60) / (186 − 60) = 84 % → Z4.
        let reserve = HeartRateZoneConfiguration(method: .heartRateReserve, maxHeartRate: 186, restingHeartRate: 60)
        let personal = IntensityClassifier.classify(run7, maxHeartRate: 186, zones: reserve)
        #expect(personal.basis == .personalZones)
        #expect(personal.kind == .tempo)
        // FC máxima validada (% de la máxima): 89 % → tempo.
        #expect(IntensityClassifier.classify(run7, maxHeartRate: 186).basis == .heartRate)
        // Sin pulso ni ritmo, RPE; sin nada, conservador.
        let blind = WorkoutSummary(activity: .outdoorRun, start: run7.start, duration: 1800, distanceMeters: nil, averageHeartRate: nil, maxHeartRate: nil, activeEnergyKilocalories: nil, averageCadence: nil, origin: .demo)
        #expect(IntensityClassifier.classify(blind, maxHeartRate: 186, perceivedEffort: 3).basis == .perceivedEffort)
        #expect(IntensityClassifier.classify(blind, maxHeartRate: 186).kind == .unknown)
    }

    @Test func perceivedIntensityIsKeptApart() {
        let run7 = NovemberFixture.run(11, 7, 9)
        let intensity = IntensityClassifier.classify(run7, maxHeartRate: 186, perceivedEffort: 3, plannedKind: .long)
        #expect(intensity.kind == .tempo)
        #expect(intensity.rpe == 3)
        #expect(intensity.perceived == .easy)
        #expect(intensity.perceptionDiffers)
        #expect(intensity.planCompliance == .harder)
        #expect(intensity.harderThanPlanned)
        // 160 lpm con una máxima de 230 (70 %): suave, en un día de umbral.
        let easierThanPlanned = IntensityClassifier.classify(NovemberFixture.run(10, 29, 18), maxHeartRate: 230, plannedKind: .tempo)
        #expect(easierThanPlanned.planCompliance == .easier)
    }

    // MARK: Sueño

    @Test func napOfTheSeventhIsAttributedToTheSeventh() throws {
        // Caso del 8/11 07:26: siesta el 7/11 (14:05–15:36, 1,52 h) y noche 23:38–06:46.
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        let samples = [
            SleepSample(start: at(7, 14, 5), end: at(7, 15, 36), stage: .asleepCore, sourceName: "Watch"),
            SleepSample(start: at(7, 23, 38), end: at(8, 6, 46), stage: .asleepCore, sourceName: "Watch"),
        ]
        let night = try #require(SleepAnalysis.night(samples, endingOn: at(8, 0, 0), calendar: calendar, origin: .demo))
        #expect(night.sleepStart == at(7, 23, 38))
        let mainHours: Double = night.mainAsleep / 3600
        #expect(abs(mainHours - 7.133) < 0.01)
        #expect(night.episodeList.count == 2)
        let days = SleepAttribution.days([night], now: at(8, 7, 26), calendar: calendar)
        let seventh = try #require(days[calendar.startOfDay(for: at(7, 0, 0))])
        let eighth = try #require(days[calendar.startOfDay(for: at(8, 0, 0))])
        let napHours: Double = seventh.naps / 3600
        #expect(abs(napHours - 1.517) < 0.01)
        #expect(seventh.main == 0)
        #expect(eighth.naps == 0)
        #expect(abs(eighth.main - night.mainAsleep) < 1)
    }

    @Test func episodesAfterNowAreIgnoredAndDuplicatesCountOnce() throws {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: hour, minute: minute))!
        }
        let samples = [
            SleepSample(start: at(0), end: at(6), stage: .asleepCore, sourceName: "Watch"),
            SleepSample(start: at(0, 30), end: at(5), stage: .asleepCore, sourceName: "Phone"),
            SleepSample(start: at(10), end: at(11), stage: .asleepCore, sourceName: "Watch"),
        ]
        let night = try #require(SleepAnalysis.night(samples, endingOn: at(0), calendar: calendar, origin: .demo))
        // Las dos fuentes se fusionan: 6 h, no 10,5.
        #expect(abs(night.mainAsleep - 21_600) < 1)
        // A las 7:26 la siesta de las 10:00 todavía no existía.
        let early = SleepAttribution.days([night, night], now: at(7, 26), calendar: calendar)
        #expect(early[calendar.startOfDay(for: at(0))]?.naps == 0)
        #expect(abs((early[calendar.startOfDay(for: at(0))]?.main ?? 0) - 21_600) < 1)
    }
}
