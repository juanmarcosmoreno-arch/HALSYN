import Foundation

/// Una pantalla de la sesión de carrera en el reloj (se pasa de una a otra en horizontal).
/// Los controles van siempre a la izquierda de todo y no se ordenan.
public enum RunPage: Hashable, Sendable {
    /// Anillo del tramo (solo con entrenamiento del plan o series).
    case interval
    /// Detalle del tramo (solo con entrenamiento del plan o series).
    case intervalDetail
    /// Pantalla de datos configurada, por su id.
    case screen(String)
    case chart
    /// Mapa (solo al aire libre).
    case map
    case laps

    /// Identificador que se guarda en los ajustes.
    public var storageID: String {
        switch self {
        case .interval: return "interval"
        case .intervalDetail: return "intervalDetail"
        case .screen(let id): return "screen:" + id  // nolocalize
        case .chart: return "chart"
        case .map: return "map"
        case .laps: return "laps"
        }
    }

    public init?(storageID: String) {
        switch storageID {
        case "interval": self = .interval
        case "intervalDetail": self = .intervalDetail
        case "chart": self = .chart
        case "map": self = .map
        case "laps": self = .laps
        default:
            let prefix = "screen:"  // nolocalize
            guard storageID.hasPrefix(prefix), storageID.count > prefix.count else { return nil }
            self = .screen(String(storageID.dropFirst(prefix.count)))
        }
    }
}

extension RunSettings {
    /// Orden predeterminado: tramo, detalle del tramo, pantallas de datos, gráfico, mapa y vueltas.
    public var defaultPageOrder: [RunPage] {
        [.interval, .intervalDetail] + validScreens.map { RunPage.screen($0.id) } + [.chart, .map, .laps]
    }

    /// Orden de las pantallas de la sesión. Siempre contiene cada pantalla una sola vez:
    /// las desconocidas o borradas se quitan y las nuevas se agregan junto a la que
    /// les precede en el orden predeterminado.
    public var pageOrder: [RunPage] {
        get {
            let defaults = defaultPageOrder
            var result: [RunPage] = []
            for page in (pageOrderIDs ?? []).compactMap(RunPage.init(storageID:)) where defaults.contains(page) && !result.contains(page) {
                result.append(page)
            }
            for (index, page) in defaults.enumerated() where !result.contains(page) {
                let previous = defaults[..<index].last { result.contains($0) }
                let position = previous.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                result.insert(page, at: position)
            }
            return result
        }
        set {
            pageOrderIDs = newValue.map(\.storageID)
            // Las pantallas de datos quedan en el mismo orden relativo.
            let screenIDs = newValue.compactMap { page -> String? in
                if case .screen(let id) = page { return id }
                return nil
            }
            let sorted = screens.sorted { lhs, rhs in
                (screenIDs.firstIndex(of: lhs.id) ?? Int.max) < (screenIDs.firstIndex(of: rhs.id) ?? Int.max)
            }
            screens = sorted
        }
    }

    /// Mueve pantallas del orden (como `List.onMove`).
    public mutating func movePages(fromOffsets source: IndexSet, toOffset destination: Int) {
        let order = pageOrder
        let moving = source.filter { order.indices.contains($0) }.map { order[$0] }
        var rest: [RunPage] = []
        for (index, page) in order.enumerated() where !source.contains(index) {
            rest.append(page)
        }
        let insertAt = min(rest.count, max(0, destination - source.filter { $0 < destination }.count))
        rest.insert(contentsOf: moving, at: insertAt)
        pageOrder = rest
    }

    /// Pantallas que se muestran en una sesión concreta, en el orden elegido.
    public func pages(hasPlan: Bool, isIndoor: Bool) -> [RunPage] {
        pageOrder.filter { page in
            switch page {
            case .interval, .intervalDetail: return hasPlan
            case .map: return !isIndoor
            case .screen, .chart, .laps: return true
            }
        }
    }
}
