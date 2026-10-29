import Foundation
import Testing
@testable import HalsynCore

@Suite("Balanza Xiaomi por Bluetooth")
struct XiaomiScaleTests {
    @Test func miSmartScale2() throws {
        // Captura publicada (xiaomi-ble): estable, kg, 86,55 kg.
        let reading = try #require(XiaomiScaleParser.parse(serviceUUID: "181D", data: [0x22, 0x9E, 0x43, 0xE5, 0x07, 0x04, 0x0B, 0x10, 0x13, 0x01]))
        #expect(reading.model == .weightOnly)
        #expect(abs(reading.weightKilograms - 86.55) < 0.001)
        #expect(reading.isStabilized && !reading.isLoadRemoved && reading.impedance == nil)
        // Libras: raw/100.
        let pounds = try #require(XiaomiScaleParser.parse(serviceUUID: "181d", data: [0x23, 0x20, 0x4E, 0xE5, 0x07, 0x04, 0x0B, 0x10, 0x13, 0x01]))
        #expect(abs(pounds.weightKilograms - 200 * 0.45359237) < 0.001)
    }

    @Test func bodyCompositionScale() throws {
        // Estable con impedancia: 428 Ω, 85,15 kg.
        let stable = try #require(XiaomiScaleParser.parse(serviceUUID: "181B", data: [0x02, 0x26, 0xB2, 0x07, 0x05, 0x04, 0x0F, 0x02, 0x01, 0xAC, 0x01, 0x86, 0x42]))
        #expect(stable.model == .bodyComposition)
        #expect(abs(stable.weightKilograms - 85.15) < 0.001)
        #expect(stable.impedance == 428 && stable.isStabilized && !stable.isLoadRemoved)
        // Pesando todavía: 94,3 kg sin impedancia ni estabilidad.
        let moving = try #require(XiaomiScaleParser.parse(serviceUUID: "181B", data: [0x02, 0x04, 0xB2, 0x07, 0x01, 0x03, 0x13, 0x1A, 0x13, 0x00, 0x00, 0xAC, 0x49]))
        #expect(abs(moving.weightKilograms - 94.3) < 0.001)
        #expect(!moving.isStabilized && moving.impedance == nil)
        // Captura real estable (486 Ω, 95,2 kg) y la misma tras bajarse.
        let real = try #require(XiaomiScaleParser.parse(serviceUUID: "181B", data: [0x02, 0x26, 0xB2, 0x07, 0x01, 0x03, 0x13, 0x1A, 0x15, 0xE6, 0x01, 0x60, 0x4A]))
        #expect(real.impedance == 486 && abs(real.weightKilograms - 95.2) < 0.001)
        let removed = try #require(XiaomiScaleParser.parse(serviceUUID: "181B", data: [0x02, 0xA6, 0xB2, 0x07, 0x01, 0x03, 0x13, 0x1A, 0x15, 0xE6, 0x01, 0x60, 0x4A]))
        #expect(removed.isLoadRemoved && removed.isStabilized)
    }

    @Test func rejectsOtherPayloads() {
        #expect(XiaomiScaleParser.parse(serviceUUID: "181B", data: [0x02, 0x26]) == nil)
        #expect(XiaomiScaleParser.parse(serviceUUID: "FE95", data: Array(repeating: 0, count: 13)) == nil)
        // Reposo (peso 0) no es una lectura.
        #expect(XiaomiScaleParser.parse(serviceUUID: "181D", data: [0x80, 0x00, 0x00, 0xE5, 0x07, 0x04, 0x0B, 0x10, 0x13, 0x01]) == nil)
    }

    @Test func jebbEquationWithHeightInMetres() throws {
        // Hombre medio del estudio: 1,77 m, 81 kg, 43,8 años, 480 Ω → ~22,4 por ciento.
        let man = try #require(BodyFatEstimate.jebb2000(weightKilograms: 81, heightMeters: 1.77, age: 43.8, sex: .male, impedance: 480))
        #expect(abs(man.percent - 22.4) < 0.1)
        #expect(man.lower == man.percent - 8 && man.upper == man.percent + 8)
        // Mujer media: 1,65 m, 70,3 kg, 40,4 años, 560 Ω → ~35,5 por ciento.
        let woman = try #require(BodyFatEstimate.jebb2000(weightKilograms: 70.3, heightMeters: 1.65, age: 40.4, sex: .female, impedance: 560))
        #expect(abs(woman.percent - 35.5) < 0.1)
        // Fuera de la población del estudio, sin estimación.
        #expect(BodyFatEstimate.jebb2000(weightKilograms: 81, heightMeters: 1.77, age: 12, sex: .male, impedance: 480) == nil)
        #expect(BodyFatEstimate.jebb2000(weightKilograms: 150, heightMeters: 1.70, age: 40, sex: .male, impedance: 480) == nil)
        #expect(BodyFatEstimate.jebb2000(weightKilograms: 81, heightMeters: 1.77, age: 40, sex: .male, impedance: 0) == nil)
    }
}
