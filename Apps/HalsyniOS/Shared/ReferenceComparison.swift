import HalsynCore
import HalsynDesign
import Observation
import SwiftUI

/// Fecha de nacimiento y sexo para las referencias por edad. Se guardan solo en
/// este iPhone; se pueden escribir a mano o copiar de Salud.
@MainActor
@Observable
final class ReferenceProfileStore {
    static let shared = ReferenceProfileStore()

    static let birthDateKey = "halsyn.profile.birthDate"
    static let sexKey = "halsyn.profile.sex"
    static let heightKey = "halsyn.profile.heightCm"

    var birthDate: Date? {
        didSet { defaults.set(birthDate?.timeIntervalSinceReferenceDate, forKey: Self.birthDateKey) }
    }
    var sex: ReferenceSex? {
        didSet { defaults.set(sex?.rawValue, forKey: Self.sexKey) }
    }
    /// Altura en centímetros (para el IMC).
    var heightCentimeters: Double? {
        didSet { defaults.set(heightCentimeters, forKey: Self.heightKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        birthDate = (defaults.object(forKey: Self.birthDateKey) as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
        sex = defaults.string(forKey: Self.sexKey).flatMap(ReferenceSex.init(rawValue:))
        heightCentimeters = defaults.object(forKey: Self.heightKey) as? Double
    }

    var age: Int? {
        birthDate.flatMap { ReferencePercentileEngine.age(birthDate: $0, on: .now, calendar: .current) }
    }

    var isComplete: Bool { age != nil && sex != nil }

    /// Copia lo que Salud tenga. Devuelve `false` si Salud no da nada.
    func importFromHealth(_ provider: any HealthDataProviding) async -> Bool {
        let characteristics = await provider.userCharacteristics()
        if let date = characteristics.birthDate { birthDate = date }
        if let value = characteristics.sex { sex = value }
        if let meters = characteristics.heightMeters { heightCentimeters = (meters * 1000).rounded() / 10 }
        return characteristics.birthDate != nil || characteristics.sex != nil || characteristics.heightMeters != nil
    }
}

/// Perfil con el que se compara: el del usuario o, en demo y sin perfil, uno de ejemplo.
struct ReferenceSubject: Equatable {
    let age: Int
    let sex: ReferenceSex
    let isExample: Bool

    @MainActor
    static func current(isDemo: Bool, store: ReferenceProfileStore = .shared) -> ReferenceSubject? {
        if let age = store.age, let sex = store.sex {
            return ReferenceSubject(age: age, sex: sex, isExample: false)
        }
        return isDemo ? ReferenceSubject(age: 35, sex: .male, isExample: true) : nil
    }
}

/// Textos de la comparación por edad.
enum ReferenceText {
    /// "hombres de 30 a 39 años", "mujeres de 80 años o más".
    static func group(_ row: ReferenceRow) -> String {
        let fromAge = row.ageRange.lowerBound
        let toAge = row.ageRange.upperBound
        switch (row.sex, toAge >= 120) {
        case (.male, true): return String(localized: "hombres de \(fromAge) años o más")
        case (.female, true): return String(localized: "mujeres de \(fromAge) años o más")
        case (.male, false): return String(localized: "hombres de \(fromAge) a \(toAge) años")
        case (.female, false): return String(localized: "mujeres de \(fromAge) a \(toAge) años")
        }
    }

    /// Frase principal, siempre en términos de "de cada 100" y sin juicio clínico.
    static func headline(_ position: ReferencePosition) -> String {
        let group = group(position.row)
        switch position.bound {
        case .within(let percentile):
            let lower = Int(percentile.rounded())
            return String(localized: "En la muestra de \(group), unas \(lower) de cada 100 personas tienen un valor más bajo que el tuyo.")
        case .below(let percentile):
            let text = HalsynReferenceStrip.percentileText(percentile)
            return String(localized: "Tu valor es más bajo que el percentil \(text) de \(group): por debajo de lo que cubre la tabla.")
        case .above(let percentile):
            let text = HalsynReferenceStrip.percentileText(percentile)
            return String(localized: "Tu valor es más alto que el percentil \(text) de \(group): por encima de lo que cubre la tabla.")
        }
    }

    /// Qué significa la dirección en este indicador.
    static func direction(_ kind: MetricKind) -> LocalizedStringKey {
        switch kind {
        case .restingHeartRate:
            "Una FC en reposo más baja suele asociarse a mejor forma aeróbica, aunque también influyen la genética, el estrés, el sueño y la medicación."
        default:
            "Un VO₂ máx. más alto indica más capacidad aeróbica. Es una de las medidas de forma física más estudiadas."
        }
    }
}

/// Indicadores con tabla de referencia verificada.
extension MetricKind {
    var hasAgeReference: Bool { ReferenceLibrary.datasets.contains { $0.metric == self } }
}

/// Tarjeta "Tu grupo de edad" para un indicador: tabla, posición y fuente.
struct ReferenceComparisonCard: View {
    let kind: MetricKind
    /// En la lista de INSIKT: versión breve, sin fuente detallada.
    var compact = false

    @Environment(AppModel.self) private var model
    @State private var reading: MetricReading?
    @State private var loaded = false
    @State private var showsProfile = false
    private var store: ReferenceProfileStore { .shared }

    private var dataset: ReferenceDataset? { ReferenceLibrary.datasets.first { $0.metric == kind } }
    private var subject: ReferenceSubject? { ReferenceSubject.current(isDemo: model.isDemo, store: store) }

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                HStack {
                    HalsynSectionHeader(compact ? kind.shortTitle : String(localized: "Tu grupo de edad"), eyebrow: compact ? nil : HalsynLexicon.form.rawValue)
                    Spacer()
                    if model.isDemo { HalsynDemoBadge() }
                }
                content
            }
        }
        .sheet(isPresented: $showsProfile) {
            NavigationStack {
                Form { ReferenceProfileSection() }
                    .navigationTitle("Edad y sexo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { showsProfile = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .task(id: model.reloadKey) {
            reading = await model.provider.latest(kind, on: .now).reading
            loaded = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if let dataset {
            if let subject {
                if let reading {
                    if let position = ReferencePercentileEngine.position(of: reading.value, metric: kind, age: subject.age, sex: subject.sex) {
                        comparison(position, reading: reading, subject: subject)
                    } else {
                        message("La tabla publicada no cubre tu edad (\(subject.age) años), así que no te comparamos.")
                    }
                } else if loaded {
                    message("Aún no hay un valor reciente de este indicador para comparar.")
                } else {
                    HalsynLoadingState()
                }
            } else {
                message("Para compararte con tu grupo hacen falta tu edad y tu sexo. Se guardan solo en este iPhone.")
                if !compact {
                    Button {
                        showsProfile = true
                    } label: {
                        Label("Añadir edad y sexo", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if !compact { source(dataset) }
        }
    }

    private func comparison(_ position: ReferencePosition, reading: MetricReading, subject: ReferenceSubject) -> some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.m) {
            if let percentile = position.percentile {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Percentil \(percentile)")
                        .font(.halsynTitle.monospacedDigit())
                        .foregroundStyle(.halsynPrimaryText)
                    Text(verbatim: "≈")
                        .foregroundStyle(.halsynSecondaryText)
                        .accessibilityHidden(true)
                }
            }
            Text(verbatim: ReferenceText.headline(position))
                .font(.halsynBody)
                .foregroundStyle(.halsynPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
            HalsynReferenceStrip(position: position, unit: unit, format: format)
            if let median = position.median {
                Text("Mediana del grupo: \(format(median)) \(unit). Tu último valor: \(format(reading.value)) \(unit).")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
            }
            if !compact {
                Text(ReferenceText.direction(kind))
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if subject.isExample {
                HalsynStatusIndicator(.neutral, text: "Perfil de ejemplo (hombre de 35 años). Añade el tuyo en Perfil.")
            }
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.halsynBody)
            .foregroundStyle(.halsynSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Fuente, población, método y limitaciones: siempre a la vista.
    private func source(_ dataset: ReferenceDataset) -> some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            Divider()
            Label("Limitaciones", systemImage: "exclamationmark.circle")
                .font(.halsynCaption.weight(.semibold))
                .foregroundStyle(.halsynPrimaryText)
            ForEach(dataset.caveats, id: \.self) { caveat in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Text(LocalizedStringKey(caveat))
                }
                .font(.halsynCaption)
                .foregroundStyle(.halsynSecondaryText)
            }
            Label("Fuente", systemImage: "book.closed")
                .font(.halsynCaption.weight(.semibold))
                .foregroundStyle(.halsynPrimaryText)
                .padding(.top, HalsynSpacing.xs)
            Group {
                Text(LocalizedStringKey(dataset.population))
                Text(LocalizedStringKey(dataset.method))
                if let url = URL(string: dataset.url) {
                    Link(destination: url) {
                        Text(verbatim: dataset.citation)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text(verbatim: dataset.citation)
                }
            }
            .font(.halsynCaption)
            .foregroundStyle(.halsynSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unit: String {
        switch kind {
        case .restingHeartRate: "lpm"
        case .vo2Max: "mL/kg/min"
        default: ""
        }
    }

    private func format(_ value: Double) -> String {
        kind == .vo2Max ? HalsynFormat.decimal(value, fractionDigits: 1) : HalsynFormat.integer(value)
    }
}

/// Aviso para la HRV: no hay una tabla comparable con la medida del reloj.
struct NoAgeReferenceNote: View {
    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Tu grupo de edad", eyebrow: HalsynLexicon.puls.rawValue)
                Text("Para la HRV no mostramos percentiles por edad: las tablas publicadas usan registros de 5 minutos o de 24 horas, en condiciones controladas, y no son comparables con las lecturas sueltas del Apple Watch. Aquí la comparación útil es contigo mismo.")
                    .font(.halsynBody)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Edad y sexo para las referencias (Perfil y hoja de la tarjeta).
struct ReferenceProfileSection: View {
    @Environment(AppModel.self) private var model
    @State private var importFailed = false
    @State private var importing = false
    private var store: ReferenceProfileStore { .shared }

    private var birthDate: Binding<Date> {
        Binding {
            store.birthDate ?? Calendar.current.date(byAdding: .year, value: -35, to: .now) ?? .now
        } set: { store.birthDate = $0 }
    }

    private var sex: Binding<ReferenceSex?> {
        Binding { store.sex } set: { store.sex = $0 }
    }

    var body: some View {
        Section {
            if store.birthDate == nil {
                Button {
                    store.birthDate = birthDate.wrappedValue
                } label: {
                    Label("Añadir fecha de nacimiento", systemImage: "calendar.badge.plus")
                }
            } else {
                DatePicker("Fecha de nacimiento", selection: birthDate, in: ...Date.now, displayedComponents: .date)
                if let age = store.age {
                    LabeledContent("Edad", value: String(localized: "\(age) años"))
                }
            }
            HeightRow()
            Picker("Sexo (tablas de referencia)", selection: sex) {
                Text("Sin indicar").tag(ReferenceSex?.none)
                ForEach(ReferenceSex.allCases) { option in
                    Text(LocalizedStringKey(option.title)).tag(ReferenceSex?.some(option))
                }
            }
            if !model.isDemo {
                Button {
                    Task {
                        importing = true
                        importFailed = !(await store.importFromHealth(model.provider))
                        importing = false
                    }
                } label: {
                    Label("Usar los datos de Salud", systemImage: "heart.text.square")
                }
                .disabled(importing)
            }
            if store.birthDate != nil || store.sex != nil || store.heightCentimeters != nil {
                Button("Borrar edad, sexo y altura", role: .destructive) {
                    store.birthDate = nil
                    store.sex = nil
                    store.heightCentimeters = nil
                }
            }
        } header: {
            Text("Tu cuerpo")
        } footer: {
            if importFailed {
                Text("Salud no ha compartido tu fecha de nacimiento, tu sexo ni tu altura. Puedes escribirlos aquí.")
            } else {
                Text("Edad y sexo biológico solo se usan para compararte con tablas científicas publicadas (VO₂ máx. y FC en reposo); la altura, para el IMC. Se guardan solo en este iPhone.")
            }
        }
    }
}

/// Altura en cm (o pulgadas con unidades imperiales).
private struct HeightRow: View {
    @AppStorage(AppPreferences.unitSystemKey) private var unitSystem: UnitSystem = .metric
    private var store: ReferenceProfileStore { .shared }

    private var isImperial: Bool { unitSystem == .imperial }

    private var value: Binding<Double> {
        Binding {
            let centimeters = store.heightCentimeters ?? 170
            return isImperial ? (centimeters / 2.54).rounded() : centimeters.rounded()
        } set: { newValue in
            store.heightCentimeters = isImperial ? (newValue * 2.54 * 10).rounded() / 10 : newValue
        }
    }

    var body: some View {
        if store.heightCentimeters == nil {
            Button {
                store.heightCentimeters = 170
            } label: {
                Label("Añadir altura", systemImage: "ruler")
            }
        } else {
            Stepper(value: value, in: isImperial ? 39...98 : 100...250, step: 1) {
                LabeledContent("Altura") {
                    Text(verbatim: isImperial ? feetAndInches : "\(Int(value.wrappedValue)) cm")
                        .monospacedDigit()
                }
            }
        }
    }

    private var feetAndInches: String {
        let inches = Int(value.wrappedValue)
        return String(inches / 12) + " ft " + String(inches % 12) + " in"
    }
}
