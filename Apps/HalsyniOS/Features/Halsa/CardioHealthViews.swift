import HalsynCore
import HalsynDesign
import Observation
import SwiftUI

/// Datos de Life's Essential 8 que se escriben a mano. Solo en este iPhone.
@MainActor
@Observable
final class CardioInputsStore {
    static let shared = CardioInputsStore()
    static let key = "halsyn.cardio.inputs"

    var inputs: CardioHealthInputs {
        didSet {
            if let data = try? JSONEncoder().encode(inputs) { defaults.set(data, forKey: Self.key) }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        inputs = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(CardioHealthInputs.self, from: $0) } ?? CardioHealthInputs()
    }
}

/// Carga mediciones + datos escritos y calcula el resultado.
@MainActor
private func loadCardioHealth(_ model: AppModel) async -> (CardioHealthMeasurements, CardioHealthResult) {
    let height = ReferenceProfileStore.shared.heightCentimeters.map { $0 / 100 }
    let measurements = await model.provider.cardioHealthMeasurements(on: .now, heightMeters: height, calendar: .current)
    return (measurements, CardiovascularHealthEngine.evaluate(measurements: measurements, inputs: CardioInputsStore.shared.inputs))
}

// MARK: - Tarjeta en HÄLSA

struct CardioHealthCard: View {
    @Environment(AppModel.self) private var model
    @State private var result: CardioHealthResult?

    var body: some View {
        NavigationLink {
            CardioHealthView()
        } label: {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.m) {
                    HStack {
                        HalsynSectionHeader("Salud cardiovascular", eyebrow: HalsynModule.halsa.brandName)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.halsynSecondaryText)
                            .accessibilityHidden(true)
                    }
                    if let result {
                        HStack(spacing: HalsynSpacing.l) {
                            HalsynScoreRing(score: result.score, lineWidth: 8)
                                .frame(width: 84)
                            VStack(alignment: .leading, spacing: 4) {
                                if let level = result.level {
                                    Text(LocalizedStringKey(level.title))
                                        .font(.halsynHeadline)
                                        .foregroundStyle(.halsynPrimaryText)
                                }
                                let have = result.available.count
                                Text("\(have) de 8 componentes de Life's Essential 8 (American Heart Association)")
                                    .font(.halsynCaption)
                                    .foregroundStyle(.halsynSecondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                if result.score == nil {
                                    Text("Completa tus datos para ver la puntuación.")
                                        .font(.halsynCaption.weight(.semibold))
                                        .foregroundStyle(.halsynAccentText)
                                }
                            }
                        }
                    } else {
                        HalsynLoadingState()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(model.reloadKey)|\(CardioInputsStore.shared.inputs.hashValue)") {
            result = await loadCardioHealth(model).1
        }
    }
}

// MARK: - Detalle

struct CardioHealthView: View {
    @Environment(AppModel.self) private var model
    @State private var measurements: CardioHealthMeasurements?
    @State private var result: CardioHealthResult?
    @State private var editing: CardioComponent?
    private var store: CardioInputsStore { .shared }

    var body: some View {
        HalsynScreen {
            if let result, let measurements {
                summary(result)
                ForEach(result.components) { item in
                    componentCard(item, measurements: measurements)
                }
                aboutCard
            } else {
                HalsynLoadingState()
            }
        }
        .navigationTitle(Text("Salud cardiovascular"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(model.reloadKey)|\(store.inputs.hashValue)") {
            let loaded = await loadCardioHealth(model)
            measurements = loaded.0
            result = loaded.1
        }
        .sheet(item: $editing) { component in
            CardioInputEditor(component: component)
        }
    }

    private func summary(_ result: CardioHealthResult) -> some View {
        HalsynCard {
            VStack(spacing: HalsynSpacing.m) {
                HStack {
                    Text(verbatim: HalsynModule.halsa.brandName).halsynEyebrowStyle()
                    Spacer()
                    if model.isDemo { HalsynDemoBadge() }
                }
                HalsynScoreRing(score: result.score, caption: result.level?.title)
                    .frame(maxWidth: 200)
                let have = result.available.count
                Text("\(have) de 8 componentes con dato")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                if result.score == nil {
                    Text("Hacen falta al menos 4 componentes. Escribe tus datos en los que dicen «Añadir».")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .multilineTextAlignment(.center)
                } else if !result.isComplete {
                    Text("Puntuación parcial: es la media de los componentes con dato. La AHA la define con los ocho.")
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .multilineTextAlignment(.center)
                }
                Text("Alta: 80–100 · Moderada: 50–79 · Baja: 0–49")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.halsynSecondaryText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func componentCard(_ item: CardioComponentScore, measurements: CardioHealthMeasurements) -> some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HStack {
                    Label(LocalizedStringKey(item.component.title), systemImage: item.component.systemImage)
                        .font(.halsynHeadline)
                        .foregroundStyle(.halsynPrimaryText)
                    Spacer()
                    if let points = item.points {
                        Text(verbatim: "\(points)")
                            .font(.halsynHeadline.monospacedDigit())
                            .foregroundStyle(.halsynPrimaryText)
                    }
                }
                if let points = item.points {
                    HalsynProgressBar(progress: Double(points) / 100)
                }
                Text(valueText(item.component, measurements: measurements))
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CardioTexts.bands(item.component))
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.component.isAutomatic && item.component != .diet {
                    Button {
                        editing = item.component
                    } label: {
                        Label(item.points == nil ? LocalizedStringKey("Añadir") : LocalizedStringKey("Editar"), systemImage: item.points == nil ? "plus.circle" : "pencil")
                            .font(.halsynCaption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    if let date = inputDate(item.component), date < Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now {
                        Label("Dato de hace más de un año: conviene actualizarlo.", systemImage: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(.halsynCaution)
                    }
                }
            }
        }
    }

    private func inputDate(_ component: CardioComponent) -> Date? {
        switch component {
        case .bloodPressure: store.inputs.bloodPressure?.date
        case .bloodLipids: store.inputs.lipids?.date
        case .bloodGlucose: store.inputs.glucose?.date
        default: nil
        }
    }

    private func valueText(_ component: CardioComponent, measurements: CardioHealthMeasurements) -> LocalizedStringKey {
        let inputs = store.inputs
        switch component {
        case .diet:
            return "Aún no se calcula: la AHA usa un cuestionario validado de alimentación (MEPA) que todavía no está en la app."
        case .physicalActivity:
            guard let minutes = measurements.weeklyActivityMinutes else { return "Faltan días con minutos de ejercicio en Salud." }
            let value = HalsynFormat.integer(minutes)
            return "\(value) min de ejercicio en los últimos 7 días (Apple Watch)."
        case .sleep:
            guard let hours = measurements.averageSleepHours else { return "Hacen falta al menos 7 noches registradas en las últimas 2 semanas." }
            let value = sleepText(hours * 3600)
            return "\(value) de media por noche en las últimas 2 semanas."
        case .bodyMassIndex:
            guard let bmi = measurements.bodyMassIndex else { return "Hace falta tu peso en Salud y tu altura en Perfil." }
            let value = HalsynFormat.decimal(bmi, fractionDigits: 1)
            return "IMC \(value) con tu último peso y tu altura."
        case .nicotine:
            guard let nicotine = inputs.nicotine else { return "Sin dato." }
            let status = NSLocalizedString(nicotine.status.title, comment: "")
            return nicotine.secondhandAtHome ? "\(status). Humo de otros en casa: −20." : "\(status)."
        case .bloodLipids:
            guard let lipids = inputs.lipids else { return "Sin dato. Sale de un análisis de sangre: colesterol total y HDL." }
            let value = HalsynFormat.integer(lipids.nonHDL)
            let date = lipids.date.formatted(date: .abbreviated, time: .omitted)
            return lipids.treated ? "No-HDL \(value) mg/dL (\(date)). Con medicación: −20." : "No-HDL \(value) mg/dL (\(date))."
        case .bloodGlucose:
            guard let glucose = inputs.glucose else { return "Sin dato. Sale de un análisis: glucosa en ayunas o HbA1c." }
            let date = glucose.date.formatted(date: .abbreviated, time: .omitted)
            if let a1c = glucose.hbA1c {
                let value = HalsynFormat.decimal(a1c, fractionDigits: 1)
                return "HbA1c \(value) por ciento (\(date))."
            }
            if let fasting = glucose.fastingGlucose {
                let value = HalsynFormat.integer(fasting)
                return "Glucosa en ayunas \(value) mg/dL (\(date))."
            }
            return "Con diabetes hace falta la HbA1c."
        case .bloodPressure:
            guard let pressure = inputs.bloodPressure else { return "Sin dato. Mídela sentado tras 5 minutos de reposo." }
            let value = HalsynFormat.integer(pressure.systolic) + "/" + HalsynFormat.integer(pressure.diastolic)
            let date = pressure.date.formatted(date: .abbreviated, time: .omitted)
            return pressure.treated ? "\(value) mmHg (\(date)). Con medicación: −20." : "\(value) mmHg (\(date))."
        }
    }

    private var aboutCard: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Qué es y cómo se calcula")
                Text("Life's Essential 8 es la medida de salud cardiovascular de la American Heart Association (2022). Cada uno de los ocho componentes vale de 0 a 100 según tablas publicadas, y la puntuación es su media simple. En estudios con cientos de miles de personas, una puntuación más alta se asocia a menos infartos, ictus y mortalidad.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynPrimaryText)
                Text("En HÅLSYN: la actividad usa los minutos de ejercicio del Apple Watch (la AHA cuenta doble los minutos vigorosos, así que la tuya puede estar algo infravalorada); el sueño, tu media de 2 semanas; el IMC, tu último peso y tu altura. La AHA admite dar 100 en IMC de 25 a 29,9 a personas con mucha masa muscular.")
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                Text("No es un diagnóstico ni sustituye una valoración médica. Tus datos escritos se guardan solo en este iPhone.")
                    .font(.halsynCaption.weight(.semibold))
                    .foregroundStyle(.halsynSecondaryText)
                ReferenceLinks(references: [ScienceReferences.lifesEssential8])
                Text(verbatim: "CardiovascularHealthEngine \(CardiovascularHealthEngine.version)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
    }
}

/// Bandas de puntos de cada componente, para mostrarlas tal cual.
enum CardioTexts {
    static func bands(_ component: CardioComponent) -> LocalizedStringKey {
        switch component {
        case .diet: "Puntos según el cuestionario MEPA (0–16 respuestas saludables)."
        case .physicalActivity: "≥150 min/semana: 100 · 120–149: 90 · 90–119: 80 · 60–89: 60 · 30–59: 40 · 1–29: 20 · 0: 0"
        case .sleep: "7–9 h: 100 · 9–10 h: 90 · 6–7 h: 70 · 5–6 h o ≥10 h: 40 · 4–5 h: 20 · <4 h: 0"
        case .bodyMassIndex: "<25: 100 · 25–29,9: 70 · 30–34,9: 30 · 35–39,9: 15 · ≥40: 0"
        case .nicotine: "Nunca: 100 · Dejado hace ≥5 años: 75 · 1–5 años: 50 · <1 año o vapeo: 25 · Fuma: 0 · Humo en casa: −20"
        case .bloodLipids: "Colesterol no-HDL <130 mg/dL: 100 · 130–159: 60 · 160–189: 40 · 190–219: 20 · ≥220: 0 · Con medicación: −20"
        case .bloodGlucose: "Sin diabetes: ayunas <100 mg/dL (o HbA1c <5,7) 100 · 100–125 (5,7–6,4) 60. Con diabetes, HbA1c: <7: 40 · 7–7,9: 30 · 8–8,9: 20 · 9–9,9: 10 · ≥10: 0"
        case .bloodPressure: "<120/<80: 100 · 120–129/<80: 75 · 130–139 o 80–89: 50 · 140–159 o 90–99: 25 · ≥160 o ≥100: 0 · Con medicación: −20"
        }
    }
}

// MARK: - Edición

private struct CardioInputEditor: View {
    let component: CardioComponent
    @Environment(\.dismiss) private var dismiss
    private var store: CardioInputsStore { .shared }

    @State private var systolic: Double?
    @State private var diastolic: Double?
    @State private var total: Double?
    @State private var hdl: Double?
    @State private var fasting: Double?
    @State private var hbA1c: Double?
    @State private var treated = false
    @State private var diabetes = false
    @State private var date = Date.now
    @State private var nicotine: NicotineStatus = .never
    @State private var secondhand = false

    var body: some View {
        NavigationStack {
            Form {
                switch component {
                case .bloodPressure:
                    Section {
                        numberField("Sistólica (máxima)", value: $systolic, unit: "mmHg")
                        numberField("Diastólica (mínima)", value: $diastolic, unit: "mmHg")
                        Toggle("Tomo medicación para la presión", isOn: $treated)
                        DatePicker("Fecha", selection: $date, in: ...Date.now, displayedComponents: .date)
                    } footer: {
                        Text("Usa la media de varias mediciones, sentado y tras 5 minutos de reposo.")
                    }
                case .bloodLipids:
                    Section {
                        numberField("Colesterol total", value: $total, unit: "mg/dL")
                        numberField("Colesterol HDL", value: $hdl, unit: "mg/dL")
                        Toggle("Tomo medicación para el colesterol", isOn: $treated)
                        DatePicker("Fecha del análisis", selection: $date, in: ...Date.now, displayedComponents: .date)
                    } footer: {
                        Text("El colesterol no-HDL es el total menos el HDL. Si tu análisis está en mmol/L, multiplica por 38,67.")
                    }
                case .bloodGlucose:
                    Section {
                        Toggle("Tengo diabetes", isOn: $diabetes)
                        numberField("Glucosa en ayunas", value: $fasting, unit: "mg/dL")
                        numberField("HbA1c", value: $hbA1c, unit: "%")
                        DatePicker("Fecha del análisis", selection: $date, in: ...Date.now, displayedComponents: .date)
                    } footer: {
                        Text("Con diabetes cuenta la HbA1c. Sin diabetes vale cualquiera de los dos.")
                    }
                case .nicotine:
                    Section {
                        Picker("Tabaco y vapeo", selection: $nicotine) {
                            ForEach(NicotineStatus.allCases, id: \.self) { status in
                                Text(LocalizedStringKey(status.title)).tag(status)
                            }
                        }
                        .pickerStyle(.inline)
                        Toggle("Alguien fuma dentro de casa", isOn: $secondhand)
                    }
                default:
                    EmptyView()
                }
                if hasValue {
                    Section {
                        Button("Borrar dato", role: .destructive) {
                            save(clear: true)
                        }
                    }
                }
            }
            .navigationTitle(Text(LocalizedStringKey(component.title)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save(clear: false) }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func numberField(_ title: LocalizedStringKey, value: Binding<Double?>, unit: String) -> some View {
        LabeledContent {
            HStack {
                TextField(title, value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(verbatim: unit).foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }

    private var hasValue: Bool {
        let inputs = store.inputs
        switch component {
        case .bloodPressure: return inputs.bloodPressure != nil
        case .bloodLipids: return inputs.lipids != nil
        case .bloodGlucose: return inputs.glucose != nil
        case .nicotine: return inputs.nicotine != nil
        default: return false
        }
    }

    private var canSave: Bool {
        switch component {
        case .bloodPressure:
            guard let systolic, let diastolic else { return false }
            return (60...260).contains(systolic) && (30...160).contains(diastolic) && diastolic < systolic
        case .bloodLipids:
            guard let total, let hdl else { return false }
            return (60...600).contains(total) && (10...200).contains(hdl) && hdl < total
        case .bloodGlucose:
            if let fasting, !(40...500).contains(fasting) { return false }
            if let hbA1c, !(3...20).contains(hbA1c) { return false }
            return diabetes ? hbA1c != nil : (fasting != nil || hbA1c != nil)
        case .nicotine:
            return true
        default:
            return false
        }
    }

    private func load() {
        let inputs = store.inputs
        switch component {
        case .bloodPressure:
            if let value = inputs.bloodPressure {
                systolic = value.systolic; diastolic = value.diastolic; treated = value.treated; date = value.date
            }
        case .bloodLipids:
            if let value = inputs.lipids {
                total = value.totalCholesterol; hdl = value.hdl; treated = value.treated; date = value.date
            }
        case .bloodGlucose:
            if let value = inputs.glucose {
                diabetes = value.hasDiabetes; fasting = value.fastingGlucose; hbA1c = value.hbA1c; date = value.date
            }
        case .nicotine:
            if let value = inputs.nicotine {
                nicotine = value.status; secondhand = value.secondhandAtHome
            }
        default:
            break
        }
    }

    private func save(clear: Bool) {
        var inputs = store.inputs
        switch component {
        case .bloodPressure:
            inputs.bloodPressure = clear ? nil : systolic.flatMap { s in diastolic.map { CardioHealthInputs.BloodPressure(systolic: s, diastolic: $0, treated: treated, date: date) } }
        case .bloodLipids:
            inputs.lipids = clear ? nil : total.flatMap { t in hdl.map { CardioHealthInputs.Lipids(totalCholesterol: t, hdl: $0, treated: treated, date: date) } }
        case .bloodGlucose:
            inputs.glucose = clear ? nil : CardioHealthInputs.Glucose(hasDiabetes: diabetes, fastingGlucose: fasting, hbA1c: hbA1c, date: date)
        case .nicotine:
            inputs.nicotine = clear ? nil : CardioHealthInputs.Nicotine(status: nicotine, secondhandAtHome: secondhand)
        default:
            break
        }
        store.inputs = inputs
        dismiss()
    }
}

// MARK: - Referencias

/// Lista de publicaciones con enlace.
struct ReferenceLinks: View {
    let references: [ScienceReference]

    var body: some View {
        VStack(alignment: .leading, spacing: HalsynSpacing.s) {
            Text("Referencias")
                .font(.halsynCaption.weight(.semibold))
                .foregroundStyle(.halsynPrimaryText)
            ForEach(references) { reference in
                Link(destination: reference.url) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "book.closed")
                            .accessibilityHidden(true)
                        Text(verbatim: reference.citation)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption2)
                    .foregroundStyle(.halsynAccentText)
                }
            }
        }
    }
}
