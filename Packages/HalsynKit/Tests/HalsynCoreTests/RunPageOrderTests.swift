import Foundation
import Testing
@testable import HalsynCore

@Suite("Orden de las pantallas del reloj")
struct RunPageOrderTests {
    private var two: RunSettings { RunSettings(screens: [.easyRun, .race]) }

    @Test func defaultOrderKeepsTheCurrentBehaviour() {
        let settings = two
        #expect(settings.pageOrder == [.interval, .intervalDetail, .screen(WorkoutScreenProfile.easyRun.id), .screen(WorkoutScreenProfile.race.id), .chart, .map, .laps])
    }

    @Test func moveAndRoundTrip() throws {
        var settings = two
        // Mapa (índice 5) al principio.
        settings.movePages(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        #expect(settings.pageOrder.first == .map)
        // Segunda pantalla antes que la primera: también cambia el orden de las pantallas.
        settings.movePages(fromOffsets: IndexSet(integer: 4), toOffset: 3)
        #expect(settings.screens.map(\.id) == [WorkoutScreenProfile.race.id, WorkoutScreenProfile.easyRun.id])
        let decoded = try RunSettings.decoded(from: settings.encoded())
        #expect(decoded.pageOrder == settings.pageOrder)
    }

    @Test func unknownDeletedAndNewPagesAreFixed() {
        var settings = two
        settings.pageOrderIDs = ["laps", "bogus", "screen:gone", "laps", "map"]
        let order = settings.pageOrder
        #expect(order.count == settings.defaultPageOrder.count)
        #expect(Set(order) == Set(settings.defaultPageOrder))
        #expect(order.prefix(2) == [.interval, .intervalDetail])
        #expect(order.firstIndex(of: .laps)! < order.firstIndex(of: .map)!)
        // Una pantalla nueva aparece junto a la anterior en el orden predeterminado.
        settings.pageOrderIDs = settings.pageOrder.map(\.storageID)
        let extra = WorkoutScreenProfile(id: "screen-x", name: "X", layout: .six, fields: [.distance])
        settings.screens.append(extra)
        let withExtra = settings.pageOrder
        #expect(withExtra.firstIndex(of: .screen("screen-x")) == withExtra.firstIndex(of: .screen(WorkoutScreenProfile.race.id))! + 1)
    }

    @Test func sessionPagesDependOnPlanAndPlace() {
        let settings = two
        let free = settings.pages(hasPlan: false, isIndoor: true)
        #expect(!free.contains(.interval) && !free.contains(.map))
        #expect(settings.pages(hasPlan: true, isIndoor: false).count == settings.pageOrder.count)
    }

    @Test func oldSettingsWithoutOrderDecode() throws {
        var settings = two
        settings.pageOrderIDs = nil
        var json = try JSONSerialization.jsonObject(with: settings.encoded()) as! [String: Any]
        json.removeValue(forKey: "pageOrderIDs")
        let decoded = try RunSettings.decoded(from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.pageOrder == settings.defaultPageOrder)
    }
}
