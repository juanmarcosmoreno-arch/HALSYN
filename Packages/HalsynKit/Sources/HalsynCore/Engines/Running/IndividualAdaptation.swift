import Foundation

/// Tendencia individual del VDOT y cuánto pesa frente a la referencia.
public struct AdaptationEstimate: Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        /// Menos de 3 pruebas o menos de 3 semanas entre la primera y la última:
        /// «Adaptación individual: todavía no estimable». Se usa la referencia.
        case reference
        /// Hay datos, pero pesan menos que la referencia.
        case learning
        /// La evidencia individual pesa al menos tanto como la referencia, con
        /// 4 pruebas o más en 6 semanas o más.
        case personalized
    }

    public let state: State
    /// Referencia: pauta de Daniels × factores de cumplimiento y frecuencia (VDOT/semana).
    public let referenceRate: Double
    /// Desviación de la referencia (variación entre personas).
    public let referenceSD: Double
    /// Pendiente solo con tus pruebas (mínimos cuadrados ponderados, robusta), si es estimable.
    public let dataRate: Double?
    public let dataSD: Double?
    /// Combinación de las dos (media posterior) y su desviación.
    public let rate: Double
    public let rateSD: Double
    /// Peso de tu evidencia: precisión de los datos ÷ (precisión de los datos + de la referencia).
    public let individualWeight: Double
    /// Pruebas usadas y tamaño efectivo tras la reponderación robusta (Kish).
    public let testsUsed: Int
    public let effectiveTests: Double
    /// Días entre la primera y la última prueba.
    public let spanDays: Int
    /// Pruebas con poco peso por apartarse mucho de la tendencia (Huber).
    public let downweighted: Int

    public var referenceWeight: Double { 1 - individualWeight }
}

/// Modelo de adaptación individual: aprende tu tasa de mejora (o de
/// deterioro) a partir de tus tests y competiciones confirmados.
///
/// - **Datos**: tests y competiciones confirmados (sin duplicados ni
///   entrenamientos), con su VDOT y una incertidumbre propia:
///   σᵢ = 0,7 VDOT ÷ √(tipo × distancia × calidad). 0,7 es la variabilidad de un
///   día de carrera que ya usa la proyección.
/// - **Antigüedad**: el peso de cada prueba se reduce a la mitad cada 12
///   semanas (una tendencia necesita memoria más larga que la forma actual).
/// - **Robustez**: reponderación de Huber (c = 1,5): una prueba con residuo
///   estandarizado mayor que 1,5 pesa 1,5/|z|. Tres iteraciones.
/// - **Sobredispersión**: si las pruebas se apartan de la recta más de lo que
///   explica su ruido, la varianza de la pendiente se multiplica por χ²/(n − 2).
/// - **Referencia** (previa): N(1/6 × f_cumplimiento × f_frecuencia, 0,10²)
///   VDOT/semana. 1/6 es la pauta prudente de Daniels (1 punto cada 6 semanas);
///   la desviación de 0,10 cubre desde casi sin mejora hasta 1 punto cada 4
///   semanas. Tus datos pueden llevarla a valores negativos.
/// - **Combinación**: media posterior con pesos = precisiones. El peso de tu
///   evidencia no se fija: sale de cuánta información hay.
/// - Acotada a ±0,25 VDOT/semana para no extrapolar.
/// - **No usa** (todavía) la carga ni la continuidad como predictores: con
///   pocos tests no se puede estimar su efecto sin sobreajustar.
public enum IndividualAdaptationModel {
    public static let version = "1.0"
    public static let referenceSD = 0.10
    public static let testNoise = 0.7
    public static let ageHalfLifeDays = 84.0
    public static let huber = 1.5
    public static let minimumTests = 3
    public static let minimumSpanDays = 21
    public static let personalizedTests = 4
    public static let personalizedSpanDays = 42

    /// Pauta de referencia sin ajustes (1 punto de VDOT cada 6 semanas).
    public static let baseRate = 1.0 / GoalCoach.realisticWeeksPerPoint

    public static func estimate(evidence: [PerformanceEvidence], referenceRate: Double, today: Date, calendar: Calendar) -> AdaptationEstimate {
        let todayStart = calendar.startOfDay(for: today)
        let tests = evidence.filter { item in
            guard item.kind != .trainingEffort, item.date <= today else { return false }
            switch item.role {
            case .counted, .inconsistent: return true
            default: return false
            }
        }
        func weeks(_ date: Date) -> Double {
            Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: todayStart).day ?? 0) / -7
        }
        let span = tests.isEmpty ? 0 : (calendar.dateComponents([.day], from: tests.map(\.date).min()!, to: tests.map(\.date).max()!).day ?? 0)
        let reference = AdaptationEstimate(state: .reference, referenceRate: referenceRate, referenceSD: referenceSD, dataRate: nil, dataSD: nil, rate: referenceRate, rateSD: referenceSD, individualWeight: 0, testsUsed: tests.count, effectiveTests: Double(tests.count), spanDays: span, downweighted: 0)
        guard tests.count >= minimumTests, span >= minimumSpanDays else { return reference }

        let x = tests.map { weeks($0.date) }
        let y = tests.map(\.vdot)
        let base: [Double] = tests.map { item in
            let f = item.factors
            let quality = (f?.kind ?? 0.9) * (f?.distance ?? 1) * (f?.quality ?? 1)
            let age = pow(0.5, -weeks(item.date) * 7 / ageHalfLifeDays)
            return max(quality, 0.05) * age / (testNoise * testNoise)
        }
        var w = base
        var slope = 0.0, intercept = 0.0, slopeVariance = 0.0
        var downweighted = 0
        for _ in 0..<3 {
            let total = w.reduce(0, +)
            let meanX = zip(w, x).map(*).reduce(0, +) / total
            let meanY = zip(w, y).map(*).reduce(0, +) / total
            let sxx = zip(w, x).map { $0 * ($1 - meanX) * ($1 - meanX) }.reduce(0, +)
            guard sxx > 1e-9 else { return reference }
            let sxy = (0..<tests.count).map { w[$0] * (x[$0] - meanX) * (y[$0] - meanY) }.reduce(0, +)
            slope = sxy / sxx
            intercept = meanY - slope * meanX
            slopeVariance = 1 / sxx
            // Huber sobre los pesos base (no acumulativo).
            downweighted = 0
            w = (0..<tests.count).map { index in
                let z = (y[index] - (intercept + slope * x[index])) * base[index].squareRoot()
                if abs(z) > huber {
                    downweighted += 1
                    return base[index] * huber / abs(z)
                }
                return base[index]
            }
        }
        // Sobredispersión: más dispersión que el ruido de las pruebas.
        let chi = (0..<tests.count).map { w[$0] * pow(y[$0] - (intercept + slope * x[$0]), 2) }.reduce(0, +)
        let dof = Double(tests.count - 2)
        if dof > 0 { slopeVariance *= max(1, chi / dof) }

        let dataPrecision = 1 / slopeVariance
        let priorPrecision = 1 / (referenceSD * referenceSD)
        let posteriorVariance = 1 / (dataPrecision + priorPrecision)
        let posterior = posteriorVariance * (dataPrecision * slope + priorPrecision * referenceRate)
        let weight = dataPrecision / (dataPrecision + priorPrecision)
        let bounded = min(max(posterior, -RacePerformanceModel.maximumWeeklyTrend), RacePerformanceModel.maximumWeeklyTrend)
        let squares = w.map { $0 * $0 }.reduce(0, +)
        let effective = squares > 0 ? pow(w.reduce(0, +), 2) / squares : 0
        let state: AdaptationEstimate.State = weight >= 0.5 && tests.count >= personalizedTests && span >= personalizedSpanDays ? .personalized : .learning
        return AdaptationEstimate(state: state, referenceRate: referenceRate, referenceSD: referenceSD, dataRate: slope, dataSD: slopeVariance.squareRoot(), rate: bounded, rateSD: posteriorVariance.squareRoot(), individualWeight: weight, testsUsed: tests.count, effectiveTests: effective, spanDays: span, downweighted: downweighted)
    }
}
