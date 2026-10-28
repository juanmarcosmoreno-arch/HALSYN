import HalsynCore
import HalsynDesign
import SwiftUI

/// CYKEL en el reloj: salir en bici con un toque. Potencia y cadencia llegan
/// de los sensores Bluetooth emparejados con el reloj, si los hay.
struct WatchCykelView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        List {
            LocationPermissionHint()
                .listRowBackground(Color.clear)

            Button {
                Task { await workout.startRide(indoor: false) }
            } label: {
                Label("Bici al aire libre", systemImage: "figure.outdoor.cycle")
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(HalsynPalette.darkPrimary)))

            Button {
                Task { await workout.startRide(indoor: true) }
            } label: {
                Label("Bici en interior", systemImage: "figure.indoor.cycle")
            }

            Section {
                EmptyView()
            } footer: {
                Text("¿Tienes medidor de potencia o sensor de cadencia? Emparéjalo en Ajustes › Bluetooth del reloj y HÅLSYN lo usará solo. En interior, sin sensor de velocidad no hay distancia.")
            }
        }
        .navigationTitle(Text(verbatim: HalsynModule.cykel.brandName))
        // Se pide aquí (si falta) y no durante la cuenta atrás.
        .onAppear { workout.requestLocationIfNeeded() }
    }
}

#Preview {
    NavigationStack { WatchCykelView() }
        .environment(WorkoutManager.shared)
}
