#if canImport(HealthKit) && (os(iOS) || os(watchOS))
import HalsynCore

/// Crea el proveedor de datos para cada modo. Compartido por iPhone y Apple Watch.
public enum HealthDataProviderFactory {
    public static func make(_ mode: DataMode) -> any HealthDataProviding {
        switch mode {
        case .demo: DemoHealthDataProvider()
        case .live: LiveHealthDataProvider(client: HKHealthStoreClient())
        }
    }
}
#endif
