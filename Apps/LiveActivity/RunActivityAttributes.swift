#if os(iOS)
import ActivityKit
import HalsynCore

/// Carrera del reloj en la pantalla bloqueada y la Dynamic Island del iPhone.
/// El estado son los datos que manda el reloj cada 5 s.
struct RunActivityAttributes: ActivityAttributes {
    typealias ContentState = RunLiveUpdate
}
#endif
