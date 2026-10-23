// swift-tools-version: 5.9
import PackageDescription

// HalsynKit agrupa el código compartido entre la app de iPhone y la de Apple Watch.
//
// - HalsynCore: modelos, protocolos de datos, tokens de marca, unidades y el
//   proveedor de datos demo. Solo depende de Foundation, por lo que compila y se
//   prueba también fuera de plataformas Apple (CI en Linux).
// - HalsynDesign: design system en SwiftUI (colores semánticos, tipografía,
//   componentes y el símbolo Å-persona).
// - HalsynHealthKit: adaptadores de HealthKit. Se activa solo donde HealthKit existe.
let package = Package(
    name: "HalsynKit",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "HalsynCore", targets: ["HalsynCore"]),
        .library(name: "HalsynDesign", targets: ["HalsynDesign"]),
        .library(name: "HalsynHealthKit", targets: ["HalsynHealthKit"]),
    ],
    targets: [
        .target(name: "HalsynCore"),
        .target(name: "HalsynDesign", dependencies: ["HalsynCore"]),
        .target(name: "HalsynHealthKit", dependencies: ["HalsynCore"]),
        .testTarget(name: "HalsynCoreTests", dependencies: ["HalsynCore"]),
    ]
)
