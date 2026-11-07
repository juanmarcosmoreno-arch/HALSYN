import Foundation

/// Un valor cardiometabólico o de laboratorio que ingresas tú.
///
/// Se guarda en la unidad canónica de cada tipo (mmHg, mg/dL, %, kg) y se
/// puede ingresar en la alternativa (mmol/L). Las referencias son **generales
/// para adultos**, con su fuente: sirven para ubicar un valor, no para
/// diagnosticar. Estos valores no cambian ninguna puntuación de HÅLSYN.
public struct LabResult: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case systolicPressure, diastolicPressure, fastingGlucose, hba1c
        case totalCholesterol, ldl, hdl, triglycerides, weight, other

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .systolicPressure: "Presión sistólica"
            case .diastolicPressure: "Presión diastólica"
            case .fastingGlucose: "Glucemia en ayunas"
            case .hba1c: "Hemoglobina glicada (HbA1c)"
            case .totalCholesterol: "Colesterol total"
            case .ldl: "Colesterol LDL"
            case .hdl: "Colesterol HDL"
            case .triglycerides: "Triglicéridos"
            case .weight: "Peso"
            case .other: "Otro resultado"
            }
        }

        /// Unidad canónica.
        public var unit: String {
            switch self {
            case .systolicPressure, .diastolicPressure: "mmHg"
            case .fastingGlucose, .totalCholesterol, .ldl, .hdl, .triglycerides: "mg/dL"
            case .hba1c: "%"
            case .weight: "kg"
            case .other: ""
            }
        }

        /// Unidad alternativa y el factor: canónica = alternativa × factor.
        public var alternative: (unit: String, factor: Double)? {
            switch self {
            case .fastingGlucose: ("mmol/L", 18.016)
            case .totalCholesterol, .ldl, .hdl: ("mmol/L", 38.67)
            case .triglycerides: ("mmol/L", 88.57)
            default: nil
            }
        }

        public var plausibleRange: ClosedRange<Double> {
            switch self {
            case .systolicPressure: 60...260
            case .diastolicPressure: 30...160
            case .fastingGlucose: 30...600
            case .hba1c: 3...20
            case .totalCholesterol: 50...600
            case .ldl: 10...400
            case .hdl: 5...200
            case .triglycerides: 10...3000
            case .weight: 25...350
            case .other: -1_000_000...1_000_000
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var date: Date
    /// En la unidad canónica (para `other`, en `customUnit`).
    public var value: Double
    /// Nombre y unidad para `other` (p. ej. «Ferritina», «ng/mL»).
    public var customName: String?
    public var customUnit: String?
    public var note: String?

    public init(id: UUID = UUID(), kind: Kind, date: Date, value: Double, customName: String? = nil, customUnit: String? = nil, note: String? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.value = value
        self.customName = customName
        self.customUnit = customUnit
        self.note = note
    }

    public var unit: String { kind == .other ? (customUnit ?? "") : kind.unit }
    public var isPlausible: Bool { kind.plausibleRange.contains(value) }
}

/// Dónde cae un valor frente a la referencia general.
public enum LabPosition: Hashable, Sendable {
    case below, within, above
}

/// Referencia general de adultos para un tipo, con su fuente.
public struct LabReference: Hashable, Sendable {
    /// Rango de referencia (cualquiera de los extremos puede faltar).
    public let lower: Double?
    public let upper: Double?
    /// Descripción breve de la referencia, en la unidad canónica.
    public let summary: String
    /// Fuente abreviada (guía y año).
    public let source: String

    public func position(_ value: Double) -> LabPosition {
        if let lower, value < lower { return .below }
        if let upper, value > upper { return .above }
        return .within
    }

    /// Referencias generales (no individualizadas por riesgo cardiovascular).
    public static func general(_ kind: LabResult.Kind, sex: ReferenceSex? = nil) -> LabReference? {
        switch kind {
        case .systolicPressure:
            LabReference(lower: nil, upper: 120, summary: "< 120 mmHg (no elevada)", source: "ESC 2024 · AHA/ACC 2017")
        case .diastolicPressure:
            LabReference(lower: nil, upper: 70, summary: "< 70 mmHg (no elevada, ESC); < 80 mmHg (AHA)", source: "ESC 2024 · AHA/ACC 2017")
        case .fastingGlucose:
            LabReference(lower: 70, upper: 99, summary: "70–99 mg/dL en ayunas", source: "ADA Standards of Care 2025")
        case .hba1c:
            LabReference(lower: nil, upper: 5.6, summary: "< 5,7 %", source: "ADA Standards of Care 2025")
        case .totalCholesterol:
            LabReference(lower: nil, upper: 190, summary: "< 190 mg/dL", source: "ESC/EAS 2019")
        case .ldl:
            LabReference(lower: nil, upper: 115, summary: "< 116 mg/dL con riesgo bajo; el objetivo depende de tu riesgo", source: "ESC/EAS 2019")
        case .hdl:
            sex == .female
                ? LabReference(lower: 50, upper: nil, summary: "> 50 mg/dL (mujeres)", source: "ESC/EAS 2019")
                : LabReference(lower: 40, upper: nil, summary: "> 40 mg/dL (hombres)", source: "ESC/EAS 2019")
        case .triglycerides:
            LabReference(lower: nil, upper: 149, summary: "< 150 mg/dL en ayunas", source: "ESC/EAS 2019")
        case .weight, .other:
            nil
        }
    }
}

extension Array where Element == LabResult {
    /// Resultados de un tipo, del más antiguo al más nuevo.
    public func series(_ kind: LabResult.Kind, name: String? = nil) -> [LabResult] {
        filter { $0.kind == kind && (kind != .other || $0.customName == name) }.sorted { $0.date < $1.date }
    }

    /// Cambio entre el último y el anterior, en la unidad canónica.
    public func lastChange(_ kind: LabResult.Kind) -> Double? {
        let values = series(kind)
        guard values.count >= 2 else { return nil }
        return values[values.count - 1].value - values[values.count - 2].value
    }
}
