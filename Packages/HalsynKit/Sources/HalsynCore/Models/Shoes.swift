import Foundation

/// Un par de zapatillas. La foto se guarda aparte (archivo en el dispositivo).
public struct Shoe: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Desde cuándo se usan: las carreras anteriores no se le asignan solas.
    public var startDate: Date
    /// Kilómetros que ya tenían al darlas de alta (en metros).
    public var initialDistance: Double
    /// Distancia a la que conviene revisarlas o cambiarlas (en metros).
    public var retirementDistance: Double
    public var isRetired: Bool

    public static let defaultRetirementDistance: Double = 700_000

    public init(id: UUID = UUID(), name: String, startDate: Date, initialDistance: Double = 0, retirementDistance: Double = Shoe.defaultRetirementDistance, isRetired: Bool = false) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.initialDistance = max(0, initialDistance)
        self.retirementDistance = max(100_000, retirementDistance)
        self.isRetired = isRetired
    }
}

/// Zapatillas y qué carrera se hizo con cuáles.
///
/// - Las carreras sin asignar van al par **predeterminado** si empezaron
///   después de su fecha de alta.
/// - Se puede reasignar una carrera a otro par o a "ninguno".
/// - Las caminatas no suman (las zapatillas de correr se gastan corriendo).
public struct ShoeCloset: Codable, Hashable, Sendable {
    public var shoes: [Shoe] = []
    public var defaultShoeID: UUID?
    /// Carrera (id del entrenamiento) → par elegido a mano. `nil` en el valor = ninguno.
    public var assignments: [UUID: UUID?] = [:]

    public init() {}

    public var activeShoes: [Shoe] { shoes.filter { !$0.isRetired } }

    /// Par de una carrera: el elegido a mano o, si no, el predeterminado.
    public func shoe(for workout: WorkoutSummary) -> Shoe? {
        guard workout.activity.isRun else { return nil }
        if let manual = assignments[workout.id] {
            return manual.flatMap { id in shoes.first { $0.id == id } }
        }
        guard let id = defaultShoeID, let shoe = shoes.first(where: { $0.id == id }),
              !shoe.isRetired, workout.start >= shoe.startDate else { return nil }
        return shoe
    }

    /// Distancia total del par (inicial + carreras asignadas).
    public func distance(of shoe: Shoe, workouts: [WorkoutSummary]) -> Double {
        shoe.initialDistance + workouts.filter { self.shoe(for: $0)?.id == shoe.id }.compactMap(\.distanceMeters).reduce(0, +)
    }

    public func runs(of shoe: Shoe, workouts: [WorkoutSummary]) -> Int {
        workouts.filter { self.shoe(for: $0)?.id == shoe.id }.count
    }

    /// 0…1 hacia la distancia de cambio (puede pasar de 1).
    public func wear(of shoe: Shoe, workouts: [WorkoutSummary]) -> Double {
        distance(of: shoe, workouts: workouts) / shoe.retirementDistance
    }

    public mutating func upsert(_ shoe: Shoe) {
        if let index = shoes.firstIndex(where: { $0.id == shoe.id }) {
            shoes[index] = shoe
        } else {
            shoes.append(shoe)
            if defaultShoeID == nil { defaultShoeID = shoe.id }
        }
    }

    public mutating func remove(_ id: UUID) {
        shoes.removeAll { $0.id == id }
        if defaultShoeID == id { defaultShoeID = activeShoes.first?.id }
        assignments = assignments.filter { $0.value != id }
    }

    public mutating func assign(_ workoutID: UUID, to shoeID: UUID?) {
        assignments[workoutID] = .some(shoeID)
    }
}

public enum ShoeStorage {
    public static let key = "halsyn.shoes"

    public static func load(from defaults: UserDefaults) -> ShoeCloset {
        guard let data = defaults.data(forKey: key), let closet = try? JSONDecoder().decode(ShoeCloset.self, from: data) else { return ShoeCloset() }
        return closet
    }

    public static func save(_ closet: ShoeCloset, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(closet) { defaults.set(data, forKey: key) }
    }
}
