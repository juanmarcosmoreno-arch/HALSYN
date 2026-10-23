import HalsynCore
import HalsynDesign
import SwiftUI

/// Áreas en las que el usuario quiere centrarse. Se guardan para personalizar
/// HÄLSA y MÅL en fases posteriores.
enum FocusArea: String, CaseIterable, Identifiable {
    case health, running, rest, activity

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .health: "Entender mi salud"
        case .running: "Correr mejor"
        case .rest: "Descansar mejor"
        case .activity: "Moverme más"
        }
    }

    var systemImage: String {
        switch self {
        case .health: "heart"
        case .running: "figure.run"
        case .rest: "moon"
        case .activity: "shoeprints.fill"
        }
    }
}

/// Onboarding breve: presentación, Apple Health, objetivos, unidades,
/// privacidad, permisos y primera lectura. Se puede continuar sin conceder
/// todos los permisos o con datos demo.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, health, focus, units, privacy, permissions, firstRead
    }

    let onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    @AppStorage(AppPreferences.focusAreasKey) private var focusAreasRaw = ""
    @State private var step: Step = .welcome
    @State private var isConnecting = false
    @State private var connectionFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, HalsynSpacing.l)
                .padding(.top, HalsynSpacing.m)
            ScrollView {
                content
                    .padding(HalsynSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(step)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            footer
                .padding(HalsynSpacing.l)
        }
        .background(
            ZStack {
                Color.halsynBackground
                HalsynBackdrop()
            }
            .ignoresSafeArea()
        )
        .interactiveDismissDisabled()
    }

    // MARK: Estructura

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Color.halsynAccent : Color.halsynHairline)
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Paso \(step.rawValue + 1) de \(Step.allCases.count)"))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .health: health
        case .focus: focus
        case .units: units
        case .privacy: privacy
        case .permissions: permissions
        case .firstRead: OnboardingFirstReadView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .permissions:
            VStack(spacing: HalsynSpacing.s) {
                HalsynPrimaryButton(isConnecting ? "Conectando…" : "Conectar Apple Health", systemImage: "heart.text.square") {
                    Task { await connect() }
                }
                .disabled(isConnecting)
                Button("Explorar con datos demo") {
                    Task {
                        await model.useDemoData()
                        advance()
                    }
                }
                .font(.halsynCaption)
                .foregroundStyle(.halsynAccentText)
                .frame(minHeight: 44)
            }
        case .firstRead:
            HalsynPrimaryButton("Ir a HÄLSA", systemImage: "arrow.right") {
                onFinish()
            }
        default:
            HStack {
                if step != .welcome {
                    Button("Atrás") { go(to: Step(rawValue: step.rawValue - 1)) }
                        .foregroundStyle(.halsynSecondaryText)
                        .frame(minHeight: 44)
                }
                HalsynPrimaryButton(step == .welcome ? "Empezar" : "Continuar") { advance() }
            }
        }
    }

    // MARK: Pasos

    private var welcome: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.l) {
            HalsynLogo(.vertical, height: 110)
                .frame(maxWidth: .infinity)
                .padding(.vertical, HalsynSpacing.l)
            Text("Conoce tu cuerpo. Entiende tu salud. Mejora tu vida.")
                .font(.halsynTitle)
                .foregroundStyle(.halsynPrimaryText)
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                ForEach(HalsynModule.allCases) { module in
                    HStack(spacing: HalsynSpacing.s) {
                        Image(systemName: module.systemImage)
                            .foregroundStyle(.halsynAccent)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(verbatim: module.brandName)
                            .font(.halsynHeadline)
                            .foregroundStyle(.halsynPrimaryText)
                        Text(LocalizedStringKey(module.meaning))
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text("Los nombres de los módulos son palabras suecas.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            stepHeader("Apple Health", title: "Tus datos, en contexto")
            Text("HÅLSYN lee de Apple Health lo que miden tu iPhone y tu Apple Watch para mostrarte cómo está tu cuerpo y cómo evoluciona.")
                .font(.halsynBody)
                .foregroundStyle(.halsynPrimaryText)
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    ForEach([MetricKind.restingHeartRate, .heartRateVariability, .sleepDuration, .steps, .vo2Max, .activeEnergy], id: \.self) { kind in
                        Label(LocalizedStringKey(kind.title), systemImage: kind.systemImage)
                            .font(.halsynCaption)
                            .foregroundStyle(.halsynPrimaryText)
                    }
                    Label("Entrenamientos de carrera", systemImage: "figure.run")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynPrimaryText)
                }
            }
            Text("Solo lectura: en esta versión HÅLSYN no escribe nada en Apple Health. Podrás elegir qué tipos compartir en la hoja de permisos de iOS.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            stepHeader(HalsynModule.mal.brandName, title: "¿Qué te gustaría conseguir?")
            Text("Elige uno o varios. Puedes cambiarlo después.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
            ForEach(FocusArea.allCases) { area in
                let selected = focusAreas.contains(area)
                Button {
                    toggle(area)
                } label: {
                    HStack {
                        Label(area.title, systemImage: area.systemImage)
                            .font(.halsynHeadline)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Color.halsynAccent : Color.halsynSecondaryText)
                    }
                    .foregroundStyle(.halsynPrimaryText)
                    .padding(HalsynSpacing.m)
                    .background(RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous).fill(Color.halsynSurface))
                    .overlay(
                        RoundedRectangle(cornerRadius: HalsynRadius.tile, style: .continuous)
                            .strokeBorder(selected ? Color.halsynAccent : Color.halsynHairline, lineWidth: selected ? 1.5 : 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var units: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            stepHeader(HalsynLexicon.fart.rawValue, title: "Unidades")
            Picker("Unidades", selection: $unitSystem) {
                ForEach(UnitSystem.allCases) { system in
                    Text(LocalizedStringKey(system.title)).tag(system)
                }
            }
            .pickerStyle(.segmented)
            HalsynCard {
                HStack {
                    HalsynMetric(title: "Distancia", value: HalsynFormat.distance(meters: 5210, unit: unitSystem), unit: unitSystem.distanceUnitSymbol)
                    Spacer()
                    HalsynMetric(title: "Ritmo medio", value: Pace(secondsPerKilometer: 282).formatted(in: unitSystem), unit: unitSystem.paceUnitSymbol)
                }
            }
            Text("Fechas y números siguen la configuración regional de tu iPhone.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            stepHeader("Privacidad", title: "Tus datos son tuyos")
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                Label("Local-first: tus datos se procesan en el dispositivo.", systemImage: "iphone")
                Label("Sin publicidad ni venta de datos.", systemImage: "hand.raised")
                Label("Sin envío de métricas a servicios de IA.", systemImage: "lock")
            }
            .font(.halsynBody)
            .foregroundStyle(.halsynPrimaryText)
            HalsynCard {
                Text("HÅLSYN ofrece estimaciones de bienestar y rendimiento. No es un dispositivo médico, no diagnostica enfermedades y no sustituye la valoración de un profesional sanitario.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            stepHeader("Apple Health", title: "Conecta tus datos")
            Text("iOS te mostrará la lista de datos. Puedes activar solo los que quieras: HÅLSYN funcionará con lo que compartas.")
                .font(.halsynBody)
                .foregroundStyle(.halsynPrimaryText)
            if model.authorizationState == .unavailable {
                HalsynStatusIndicator(.caution, text: "Apple Health no está disponible en este dispositivo.")
            }
            if connectionFailed {
                HalsynStatusIndicator(.caution, text: "No se pudo conectar con Apple Health. Puedes intentarlo de nuevo o continuar con datos demo.")
            }
            Text("Si prefieres, explora la app con datos de demostración claramente identificados y conecta Apple Health más tarde desde Perfil.")
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
        }
    }

    private func stepHeader(_ eyebrow: String, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(eyebrow)).halsynEyebrowStyle()
            Text(title)
                .font(.halsynLargeTitle)
                .foregroundStyle(.halsynPrimaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Acciones

    private var focusAreas: Set<FocusArea> {
        Set(focusAreasRaw.split(separator: ",").compactMap { FocusArea(rawValue: String($0)) })
    }

    private func toggle(_ area: FocusArea) {
        var areas = focusAreas
        if areas.contains(area) { areas.remove(area) } else { areas.insert(area) }
        focusAreasRaw = areas.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func connect() async {
        isConnecting = true
        connectionFailed = false
        let connected = await model.connectAppleHealth()
        isConnecting = false
        if connected {
            advance()
        } else {
            connectionFailed = true
        }
    }

    private func advance() {
        go(to: Step(rawValue: step.rawValue + 1))
    }

    private func go(to next: Step?) {
        guard let next else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { step = next }
    }
}

/// Último paso: primera lectura de datos, mostrando qué hay disponible.
private struct OnboardingFirstReadView: View {
    @Environment(AppModel.self) private var model
    @State private var results: [MetricDisplay]?

    private static let kinds: [MetricKind] = [.steps, .restingHeartRate, .heartRateVariability, .sleepDuration, .vo2Max]

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: HalsynModule.halsa.brandName).halsynEyebrowStyle()
                Text("Primera lectura")
                    .font(.halsynLargeTitle)
                    .foregroundStyle(.halsynPrimaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let results {
                HalsynCard {
                    VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                        ForEach(results, id: \.kind) { item in
                            HStack {
                                Label(LocalizedStringKey(item.kind.title), systemImage: item.kind.systemImage)
                                    .font(.halsynCaption)
                                    .foregroundStyle(.halsynPrimaryText)
                                Spacer()
                                if let value = item.value {
                                    Text(verbatim: value).font(.halsynHeadline.monospacedDigit())
                                    Text(LocalizedStringKey(item.unit)).font(.halsynCaption).foregroundStyle(.halsynSecondaryText)
                                } else {
                                    HalsynStatusIndicator(.neutral, text: "Sin datos aún")
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if model.isDemo {
                    HalsynDemoBadge()
                }
                Text("Las comparaciones con tu propio historial mejoran a medida que HÅLSYN acumula días de datos. Es normal que al principio falten algunos indicadores.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            } else {
                HalsynLoadingState("Leyendo tus datos…")
            }
        }
        .task {
            var displays: [MetricDisplay] = []
            for kind in Self.kinds {
                displays.append(MetricDisplay(await model.provider.latest(kind, on: .now), kind: kind))
            }
            results = displays
        }
    }
}

#Preview {
    OnboardingView {}
        .environment(AppModel(provider: DemoHealthDataProvider()))
}
