import Foundation

/// Estadística básica para INSIKT. Implementación propia (sin dependencias),
/// verificada en tests con valores de referencia publicados.
public enum Stats {
    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Varianza muestral (n − 1).
    public static func variance(_ values: [Double]) -> Double? {
        guard values.count > 1, let m = mean(values) else { return nil }
        return values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
    }

    public static func standardDeviation(_ values: [Double]) -> Double? {
        variance(values).map { $0.squareRoot() }
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    // MARK: Rangos y correlación

    /// Rangos con empates promediados (1-based).
    public static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = [Double](repeating: 0, count: values.count)
        var start = 0
        while start < order.count {
            var end = start
            while end + 1 < order.count && values[order[end + 1]] == values[order[start]] {
                end += 1
            }
            let rank = Double(start + end) / 2 + 1
            for position in start...end {
                result[order[position]] = rank
            }
            start = end + 1
        }
        return result
    }

    public static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count > 2, let mx = mean(x), let my = mean(y) else { return nil }
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (a, b) in zip(x, y) {
            sxy += (a - mx) * (b - my)
            sxx += (a - mx) * (a - mx)
            syy += (b - my) * (b - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    /// Correlación de Spearman (robusta a valores extremos y relaciones no lineales monótonas).
    public static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count else { return nil }
        return pearson(ranks(x), ranks(y))
    }

    /// p bilateral de una correlación con `n` pares (aproximación t con n − 2 gl).
    public static func correlationPValue(_ r: Double, n: Int) -> Double? {
        guard n > 3, abs(r) < 1 else { return abs(r) >= 1 && n > 3 ? 0 : nil }
        let df = Double(n - 2)
        let t = r * (df / (1 - r * r)).squareRoot()
        return studentTTwoSidedP(t: t, df: df)
    }

    // MARK: Contrastes

    public struct WelchResult: Hashable, Sendable {
        public let difference: Double
        public let t: Double
        public let degreesOfFreedom: Double
        public let pValue: Double
        /// d de Cohen con desviación típica combinada.
        public let effectSize: Double
    }

    /// t de Welch para dos muestras independientes (`b − a`).
    public static func welch(_ a: [Double], _ b: [Double]) -> WelchResult? {
        guard a.count > 1, b.count > 1, let ma = mean(a), let mb = mean(b), let va = variance(a), let vb = variance(b) else { return nil }
        let na = Double(a.count), nb = Double(b.count)
        let se2 = va / na + vb / nb
        let pooled = (((na - 1) * va + (nb - 1) * vb) / (na + nb - 2)).squareRoot()
        guard se2 > 0 else { return nil }
        let t = (mb - ma) / se2.squareRoot()
        let df = se2 * se2 / ((va / na) * (va / na) / (na - 1) + (vb / nb) * (vb / nb) / (nb - 1))
        guard let p = studentTTwoSidedP(t: t, df: df) else { return nil }
        return WelchResult(difference: mb - ma, t: t, degreesOfFreedom: df, pValue: p, effectSize: pooled > 0 ? (mb - ma) / pooled : 0)
    }

    /// ANOVA de un factor: p del estadístico F. `nil` si algún grupo tiene menos de 2 valores.
    public static func oneWayANOVA(_ groups: [[Double]]) -> (f: Double, pValue: Double)? {
        let valid = groups.filter { !$0.isEmpty }
        guard valid.count > 1, valid.allSatisfy({ $0.count > 1 }) else { return nil }
        let all = valid.flatMap { $0 }
        guard let grand = mean(all) else { return nil }
        let k = Double(valid.count), n = Double(all.count)
        var between = 0.0, within = 0.0
        for group in valid {
            let m = mean(group) ?? 0
            between += Double(group.count) * (m - grand) * (m - grand)
            within += group.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        }
        let d1 = k - 1, d2 = n - k
        guard d2 > 0, within > 0 else { return nil }
        let f = (between / d1) / (within / d2)
        let p = regularizedIncompleteBeta(x: d2 / (d2 + d1 * f), a: d2 / 2, b: d1 / 2)
        return (f, p)
    }

    /// Benjamini–Hochberg: valores q en el mismo orden que `pValues`.
    public static func benjaminiHochberg(_ pValues: [Double]) -> [Double] {
        let m = Double(pValues.count)
        let order = pValues.indices.sorted { pValues[$0] < pValues[$1] }
        var q = [Double](repeating: 1, count: pValues.count)
        var running = 1.0
        for (position, index) in order.enumerated().reversed() {
            running = min(running, pValues[index] * m / Double(position + 1))
            q[index] = min(running, 1)
        }
        return q
    }

    // MARK: Distribuciones

    /// p bilateral de la t de Student.
    public static func studentTTwoSidedP(t: Double, df: Double) -> Double? {
        guard df > 0, t.isFinite else { return nil }
        return regularizedIncompleteBeta(x: df / (df + t * t), a: df / 2, b: 0.5)
    }

    /// Función beta incompleta regularizada I_x(a, b) (fracción continua de Lentz).
    public static func regularizedIncompleteBeta(x: Double, a: Double, b: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let logBeta: Double = lgamma(a + b) - lgamma(a) - lgamma(b)
        let logTerms: Double = a * log(x) + b * log(1 - x)
        let front = exp(logBeta + logTerms)
        if x < (a + 1) / (a + b + 2) {
            return front * betaContinuedFraction(x: x, a: a, b: b) / a
        }
        return 1 - front * betaContinuedFraction(x: 1 - x, a: b, b: a) / b
    }

    private static func betaContinuedFraction(x: Double, a: Double, b: Double) -> Double {
        let tiny = 1e-300
        var c = 1.0
        var d = 1 - (a + b) * x / (a + 1)
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var result = d
        for m in 1...300 {
            let m = Double(m)
            let m2 = 2 * m
            let evenDenominator: Double = (a + m2 - 1) * (a + m2)
            var numerator: Double = m * (b - m) * x / evenDenominator
            d = 1 + numerator * d
            if abs(d) < tiny { d = tiny }
            c = 1 + numerator / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            result *= d * c
            let oddDenominator: Double = (a + m2) * (a + m2 + 1)
            numerator = -(a + m) * (a + b + m) * x / oddDenominator
            d = 1 + numerator * d
            if abs(d) < tiny { d = tiny }
            c = 1 + numerator / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            result *= delta
            if abs(delta - 1) < 1e-12 { break }
        }
        return result
    }
}
