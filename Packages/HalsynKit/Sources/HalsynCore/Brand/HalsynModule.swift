import Foundation

/// Módulos de producto de HÅLSYN. Los nombres suecos son marcas y no se traducen;
/// `meaning` y `summary` sí son texto de interfaz (español como idioma base).
public enum HalsynModule: String, CaseIterable, Identifiable, Sendable {
    case halsa
    case spring
    case cykel
    case vila
    case insikt
    case mal

    public var id: String { rawValue }

    /// Nombre de marca, siempre en mayúsculas y con los diacríticos suecos.
    public var brandName: String {
        switch self {
        case .halsa: "HÄLSA"
        case .spring: "SPRING"
        case .cykel: "CYKEL"
        case .vila: "VILA"
        case .insikt: "INSIKT"
        case .mal: "MÅL"
        }
    }

    /// Traducción breve, para onboarding y subtítulos.
    public var meaning: String {
        switch self {
        case .halsa: "Salud"
        case .spring: "Running"
        case .cykel: "Ciclismo"
        case .vila: "Descanso"
        case .insikt: "Análisis"
        case .mal: "Objetivos"
        }
    }

    public var summary: String {
        switch self {
        case .halsa: "Tu estado fisiológico diario, de un vistazo."
        case .spring: "Entrenamientos de carrera con métricas avanzadas."
        case .cykel: "Salidas en bici con velocidad, desnivel y potencia."
        case .vila: "Sueño, recuperación y equilibrio esfuerzo-descanso."
        case .insikt: "Tendencias, comparaciones y evolución a largo plazo."
        case .mal: "Objetivos de salud y de entrenamiento, paso a paso."
        }
    }

    /// Nombre de SF Symbol asociado. Se valida en la capa de UI.
    public var systemImage: String {
        switch self {
        case .halsa: "heart"
        case .spring: "figure.run"
        case .cykel: "bicycle"
        case .vila: "moon"
        case .insikt: "chart.bar.xaxis"
        case .mal: "target"
        }
    }
}

/// Vocabulario sueco secundario usado como etiqueta de métricas.
public enum HalsynLexicon: String, CaseIterable, Sendable {
    case puls = "PULS"
    case somn = "SÖMN"
    case steg = "STEG"
    case kraft = "KRAFT"
    case balans = "BALANS"
    case form = "FORM"
    case tid = "TID"
    case fart = "FART"
    case rorelse = "RÖRELSE"
    case kropp = "KROPP"
    case ljus = "LJUS"

    public var meaning: String {
        switch self {
        case .puls: "Frecuencia cardíaca"
        case .somn: "Sueño"
        case .steg: "Pasos"
        case .kraft: "Fuerza"
        case .balans: "Equilibrio"
        case .form: "Condición física"
        case .tid: "Tiempo"
        case .fart: "Velocidad"
        case .rorelse: "Movimiento"
        case .kropp: "Cuerpo"
        case .ljus: "Luz"
        }
    }
}

public enum HalsynBrand {
    /// Nombre comercial. Usar siempre esta constante en la interfaz.
    public static let name = "HÅLSYN"
    /// Nombre técnico sin diacríticos (targets, bundle IDs, archivos).
    public static let technicalName = "Halsyn"
    public static let tagline = "HEALTH IN MOTION"
    public static let claim = "Know your body. Understand your health. Improve your life."
}
