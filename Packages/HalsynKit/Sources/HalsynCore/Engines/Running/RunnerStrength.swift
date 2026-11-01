import Foundation

/// Ejercicios de fuerza para corredores, para los días de gimnasio. Pautas
/// habituales (Blagrove 2018: la fuerza con cargas y la pliometría mejoran la
/// economía de carrera; Lauersen 2014: el trabajo de fuerza reduce lesiones).
/// No es una prescripción: el peso y la técnica los ajusta quien te entrena.
public struct StrengthExercise: Hashable, Identifiable, Sendable {
    public enum Group: String, Hashable, CaseIterable, Sendable {
        case singleLeg, calves, hips, core, plyometrics

        public var title: String {
            switch self {
            case .singleLeg: "Piernas, de a una"
            case .calves: "Pantorrilla y tendón de Aquiles"
            case .hips: "Cadera y glúteo medio"
            case .core: "Zona media"
            case .plyometrics: "Pliometría"
            }
        }

        /// Por qué importa para correr.
        public var purpose: String {
            switch self {
            case .singleLeg: "Correr es apoyar una pierna por vez: fuerza y equilibrio en cada una."
            case .calves: "Son las que más trabajan en cada zancada; fuertes, cuidan el tendón."
            case .hips: "Mantienen la rodilla y la pelvis alineadas al apoyar."
            case .core: "Un tronco estable desperdicia menos energía, sobre todo cansado."
            case .plyometrics: "Mejoran el rebote y la economía de carrera. Solo con base de fuerza."
            }
        }

        public var symbol: String {
            switch self {
            case .singleLeg: "figure.strengthtraining.functional"
            case .calves: "figure.step.training"
            case .hips: "figure.cooldown"
            case .core: "figure.core.training"
            case .plyometrics: "figure.jumprope"
            }
        }
    }

    public let id: String
    public let group: Group
    public let name: String
    public let dose: String
    public let howTo: String

    public static let all: [StrengthExercise] = [
        StrengthExercise(id: "bulgarian", group: .singleLeg, name: "Sentadilla búlgara", dose: "3 × 6–10 por pierna", howTo: "Pie de atrás apoyado en un banco; baja recto hasta que la rodilla de atrás casi toque el suelo."),
        StrengthExercise(id: "single-leg-deadlift", group: .singleLeg, name: "Peso muerto a una pierna", dose: "3 × 8 por pierna", howTo: "Con una mancuerna, inclínate desde la cadera con la espalda recta mientras la otra pierna va hacia atrás."),
        StrengthExercise(id: "step-up", group: .singleLeg, name: "Step-up", dose: "3 × 8 por pierna", howTo: "Sube a un cajón alto con peso, empujando con la pierna de arriba, sin impulsarte con la de abajo."),
        StrengthExercise(id: "standing-calf", group: .calves, name: "Elevación de talones de pie", dose: "3 × 12–15", howTo: "Rodilla estirada, con peso; sube rápido y baja lento, en un escalón si puedes."),
        StrengthExercise(id: "seated-calf", group: .calves, name: "Elevación de talones sentado", dose: "3 × 12–15", howTo: "Rodilla doblada (trabaja el sóleo), con peso sobre los muslos; baja lento."),
        StrengthExercise(id: "glute-bridge", group: .hips, name: "Puente de glúteo a una pierna", dose: "3 × 10 por pierna", howTo: "Acostado, empuja con el talón y sube la cadera sin arquear la espalda. Con peso, hip thrust."),
        StrengthExercise(id: "band-walk", group: .hips, name: "Caminata lateral con banda", dose: "2–3 × 15 pasos por lado", howTo: "Banda por encima de las rodillas o en los tobillos, rodillas un poco dobladas, pasos cortos."),
        StrengthExercise(id: "plank", group: .core, name: "Plancha frontal y lateral", dose: "3 × 30–45 s", howTo: "Cuerpo en línea recta, sin hundir ni levantar la cadera."),
        StrengthExercise(id: "dead-bug", group: .core, name: "Dead bug", dose: "3 × 10", howTo: "Boca arriba, estira brazo y pierna contrarios sin despegar la zona lumbar del suelo."),
        StrengthExercise(id: "pogo", group: .plyometrics, name: "Saltos suaves en el lugar", dose: "2–3 × 10", howTo: "Saltos cortos y rápidos con los tobillos, casi sin doblar las rodillas."),
        StrengthExercise(id: "box-jump", group: .plyometrics, name: "Saltos al cajón o a una pierna", dose: "2–3 × 6–10", howTo: "Cae suave y estable; descansa entre series. Mejor después de unas semanas de fuerza."),
    ]

    public static func exercises(in group: Group) -> [StrengthExercise] {
        all.filter { $0.group == group }
    }
}
