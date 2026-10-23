import Foundation
import Testing
@testable import HalsynCore

@Suite("Referencias por edad")
struct ReferenceTests {
    @Test func interpolatesBetweenPublishedPercentiles() throws {
        // Hombre de 34: P50 = 42,4 y P75 = 49,2 → 46 queda algo pasada la mitad (≈ P63).
        let position = try #require(ReferencePercentileEngine.position(of: 46, metric: .vo2Max, age: 34, sex: .male))
        #expect(position.row.ageRange == 30...39)
        #expect(position.percentile == 63)
        #expect(position.median == 42.4)
        #expect(position.dataset.higherIsBetter)
    }

    @Test func exactPercentileValue() throws {
        let position = try #require(ReferencePercentileEngine.position(of: 37.6, metric: .vo2Max, age: 25, sex: .female))
        #expect(position.percentile == 50)
    }

    @Test func outsideTheTableDoesNotExtrapolate() throws {
        let high = try #require(ReferencePercentileEngine.position(of: 70, metric: .vo2Max, age: 25, sex: .male))
        #expect(high.bound == .above(95))
        #expect(high.percentile == nil)
        let low = try #require(ReferencePercentileEngine.position(of: 10, metric: .vo2Max, age: 75, sex: .female))
        #expect(low.bound == .below(5))
    }

    @Test func noReferenceOutsideCoverageOrForOtherMetrics() {
        #expect(ReferencePercentileEngine.position(of: 40, metric: .vo2Max, age: 85, sex: .male) == nil)
        #expect(ReferencePercentileEngine.position(of: 40, metric: .vo2Max, age: 18, sex: .male) == nil)
        #expect(ReferencePercentileEngine.position(of: 48, metric: .heartRateVariability, age: 40, sex: .male) == nil)
        #expect(ReferenceLibrary.vo2Max.ageCoverage == 20...79)
        #expect(ReferenceLibrary.restingHeartRate.ageCoverage == 20...120)
    }

    @Test func restingHeartRateLowerIsBetter() throws {
        // Mujer de 45: P10 = 59, P25 = 64.
        let position = try #require(ReferencePercentileEngine.position(of: 59, metric: .restingHeartRate, age: 45, sex: .female))
        #expect(position.percentile == 10)
        #expect(!position.dataset.higherIsBetter)
        // Fila de 80+ sin P1 publicado: el mínimo es P2,5.
        let old = try #require(ReferencePercentileEngine.position(of: 40, metric: .restingHeartRate, age: 85, sex: .male))
        #expect(old.bound == .below(2.5))
    }

    @Test func tablesAreMonotonic() {
        for dataset in ReferenceLibrary.datasets {
            for row in dataset.rows {
                let values = row.percentiles.sorted { $0.key < $1.key }.map(\.value)
                #expect(values == values.sorted(), "\(dataset.id) \(row.sex) \(row.ageRange)")
                #expect(row.percentiles[50] != nil)
            }
            // Sin solapes de edad dentro de cada sexo.
            for sex in ReferenceSex.allCases {
                let ranges = dataset.rows.filter { $0.sex == sex }.map(\.ageRange).sorted { $0.lowerBound < $1.lowerBound }
                for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound < b.lowerBound) }
            }
        }
    }

    @Test func ageFromBirthDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let birth = calendar.date(from: DateComponents(year: 1990, month: 10, day: 24))!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        #expect(ReferencePercentileEngine.age(birthDate: birth, on: day, calendar: calendar) == 35)
        #expect(ReferencePercentileEngine.age(birthDate: birth, on: day.addingTimeInterval(86_400), calendar: calendar) == 36)
    }
}
