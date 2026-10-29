import Foundation

/// Lectura de una balanza Xiaomi recibida por Bluetooth (publicidad BLE, sin
/// emparejar). Modelos sin cifrar que usan Zepp Life / Mi Fit:
/// - Mi Smart Scale 2 (XMTZC04HM): servicio 0x181D, 10 bytes, solo peso.
/// - Mi Body Composition Scale / Scale 2 (XMTZC02HM / XMTZC05HM): servicio
///   0x181B, 13 bytes, peso e impedancia.
/// Los modelos nuevos (S400, S200, S800) van cifrados (0xFE95) y no se pueden leer.
/// Formato: hechos de interoperabilidad documentados en xiaomi-ble (Apache-2.0),
/// ble_monitor (MIT) y la wiki de openScale.
public struct XiaomiScaleReading: Hashable, Sendable {
    public enum Model: String, Hashable, Sendable {
        /// Solo peso (0x181D).
        case weightOnly
        /// Peso e impedancia (0x181B).
        case bodyComposition
    }

    public let model: Model
    /// Peso convertido a kilogramos.
    public let weightKilograms: Double
    /// Impedancia en ohmios (pies descalzos), si la balanza la midió.
    public let impedance: Double?
    /// El peso dejó de cambiar.
    public let isStabilized: Bool
    /// Ya se bajó de la balanza (sigue anunciando la última lectura).
    public let isLoadRemoved: Bool

    /// Lectura final: estable, con la persona aún encima o recién bajada.
    public var isFinal: Bool { isStabilized }
}

public enum XiaomiScaleParser {
    public static let weightServiceUUID = "181D"
    public static let bodyCompositionServiceUUID = "181B"
    /// Impedancias que se descartan (0 = no medida; las publicaciones rechazan ≥ 3000).
    public static let plausibleImpedance: ClosedRange<Double> = 1...2999
    public static let plausibleWeight: ClosedRange<Double> = 5...300

    /// Servicio de los modelos cifrados (Xiaomi MiBeacon).
    public static let encryptedServiceUUID = "FE95"

    /// Interpreta los datos de servicio. `serviceUUID` es "181B" o "181D" (corto
    /// o en la forma larga de 128 bits del Bluetooth SIG).
    public static func parse(serviceUUID: String, data: [UInt8]) -> XiaomiScaleReading? {
        switch shortUUID(serviceUUID) {
        case weightServiceUUID where data.count >= 10:
            return parseWeightScale(Array(data.prefix(10)))
        case bodyCompositionServiceUUID where data.count >= 13:
            return parseBodyCompositionScale(Array(data.prefix(13)))
        default:
            return nil
        }
    }

    /// "0000181D-0000-1000-8000-00805F9B34FB" → "181D"; los cortos quedan igual.
    public static func shortUUID(_ uuid: String) -> String {
        let upper = uuid.uppercased()
        let base = "-0000-1000-8000-00805F9B34FB"
        if upper.count == 36, upper.hasPrefix("0000"), upper.hasSuffix(base) {
            return String(upper.dropFirst(4).prefix(4))
        }
        return upper
    }

    private static func uint16(_ data: [UInt8], _ index: Int) -> Double {
        Double(UInt16(data[index]) | UInt16(data[index + 1]) << 8)
    }

    /// 0x181D: byte 0 control (bit0 lbs, bit4 jin, bit5 estable, bit7 retirado),
    /// bytes 1-2 peso (kg = raw/200; lbs y jin = raw/100), bytes 3-9 fecha.
    private static func parseWeightScale(_ data: [UInt8]) -> XiaomiScaleReading? {
        let control = data[0]
        let raw = uint16(data, 1)
        let kilograms: Double
        if control & 0x01 != 0 {
            kilograms = raw / 100 * 0.45359237
        } else if control & 0x10 != 0 {
            kilograms = raw / 100 * 0.5
        } else {
            kilograms = raw / 200
        }
        guard plausibleWeight.contains(kilograms) else { return nil }
        return XiaomiScaleReading(
            model: .weightOnly,
            weightKilograms: kilograms,
            impedance: nil,
            isStabilized: control & 0x20 != 0,
            isLoadRemoved: control & 0x80 != 0
        )
    }

    /// 0x181B: byte 0 (bit0 lbs), byte 1 (bit1 impedancia, bit5 estable,
    /// bit6 jin, bit7 retirado), bytes 2-8 fecha, 9-10 impedancia (Ω),
    /// 11-12 peso (kg = raw/200; lbs y jin = raw/100).
    private static func parseBodyCompositionScale(_ data: [UInt8]) -> XiaomiScaleReading? {
        let control0 = data[0]
        let control1 = data[1]
        let raw = uint16(data, 11)
        let kilograms: Double
        if control0 & 0x01 != 0 {
            kilograms = raw / 100 * 0.45359237
        } else if control1 & 0x40 != 0 {
            kilograms = raw / 100 * 0.5
        } else {
            kilograms = raw / 200
        }
        guard plausibleWeight.contains(kilograms) else { return nil }
        let impedance = uint16(data, 9)
        let hasImpedance = control1 & 0x02 != 0 && plausibleImpedance.contains(impedance)
        return XiaomiScaleReading(
            model: .bodyComposition,
            weightKilograms: kilograms,
            impedance: hasImpedance ? impedance : nil,
            isStabilized: control1 & 0x20 != 0,
            isLoadRemoved: control1 & 0x80 != 0
        )
    }
}

/// Grasa corporal estimada con la ecuación de pie a pie de Jebb et al. 2000
/// (Br J Nutr), derivada con una Tanita de 50 kHz frente a un modelo de 4
/// compartimentos en 205 adultos británicos (16–78 años, IMC 16–41):
/// %grasa = −156,1 − 89,1·ln(altura m) + 45,6·ln(peso kg) + 0,120·edad
///          + 0,0494·impedancia + 19,6·ln(altura m) [solo mujeres].
/// La altura va en metros (el artículo dice cm, pero así da valores imposibles).
/// Error individual de unos ±8 puntos (95 por ciento) y no validada en balanzas
/// Xiaomi: se muestra como rango y con esas advertencias.
public struct BodyFatEstimate: Hashable, Sendable {
    public let percent: Double
    /// Margen aproximado al 95 por ciento (en puntos de grasa).
    public let margin: Double

    public var lower: Double { max(3, percent - margin) }
    public var upper: Double { min(70, percent + margin) }

    public static let margin: Double = 8
    public static let ageRange: ClosedRange<Double> = 16...78
    public static let bmiRange: ClosedRange<Double> = 16...41

    /// `nil` fuera de la población del estudio o sin datos suficientes.
    public static func jebb2000(weightKilograms: Double, heightMeters: Double, age: Double, sex: ReferenceSex, impedance: Double) -> BodyFatEstimate? {
        guard weightKilograms > 0, heightMeters > 1, heightMeters < 2.5,
              ageRange.contains(age),
              XiaomiScaleParser.plausibleImpedance.contains(impedance) else { return nil }
        let bmi = weightKilograms / (heightMeters * heightMeters)
        guard bmiRange.contains(bmi) else { return nil }
        let lnHeight = log(heightMeters)
        var percent = -156.1 - 89.1 * lnHeight + 45.6 * log(weightKilograms) + 0.120 * age + 0.0494 * impedance
        if sex == .female {
            percent += 19.6 * lnHeight
        }
        guard percent.isFinite, (2...75).contains(percent) else { return nil }
        return BodyFatEstimate(percent: percent, margin: margin)
    }
}
