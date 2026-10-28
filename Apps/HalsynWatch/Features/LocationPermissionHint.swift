import HalsynCore
import HalsynDesign
import SwiftUI

/// Aviso sobre el permiso de ubicación en SPRING y CYKEL (las listas piden el
/// permiso al abrirse, así no aparece en medio de la cuenta atrás).
struct LocationPermissionHint: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        if workout.locationWasAllowedOnce {
            hint("Para que no vuelva a preguntar en cada carrera, elige «Permitir al usar la app» y no «Permitir una vez». También en el reloj: Ajustes › Privacidad y seguridad › Localización › HÅLSYN.")
        } else if workout.locationDenied {
            hint("Sin permiso de ubicación, las carreras y salidas al aire libre no tienen ruta ni distancia por GPS. Actívalo en el reloj: Ajustes › Privacidad y seguridad › Localización › HÅLSYN.")
        }
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.caption2)
        } icon: {
            Image(systemName: "location.slash")
                .foregroundStyle(Color(HalsynPalette.cautionDark))
        }
    }
}
