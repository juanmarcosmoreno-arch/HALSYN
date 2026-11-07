import Charts
import HalsynCore
import HalsynDesign
import Observation
import SwiftUI

/// Valores cardiometabólicos y de laboratorio que ingresas tú. Solo en este iPhone.
@MainActor
@Observable
final class LabResultStore {
    static let shared = LabResultStore()
    static let key = "halsyn.labResults"

    private(set) var results: [LabResult]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        results = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([LabResult].self, from: $0) } ?? []
    }

    func save(_ result: LabResult) {
        results.removeAll { $0.id == result.id }
        results.append(result)
        results.sort { $0.date > $1.date }
        persist()
    }

    func remove(_ id: UUID) {
        results.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(results) { defaults.set(data, forKey: Self.key) }
    }
}

enum LabText {
    static func title(_ result: LabResult) -> String {
        if result.kind == .other, let name = result.customName, !name.isEmpty { return name }
        return String(localized: String.LocalizationValue(result.kind.title))
    }

    static func value(_ result: LabResult) -> String {
        let digits = result.kind == .hba1c || result.kind == .weight ? 1 : 0
        let unit = result.unit
        return HalsynFormat.decimal(result.value, fractionDigits: result.kind == .other ? 2 : digits) + (unit.isEmpty ? "" : " " + unit)
    }

    static func position(_ position: LabPosition) -> LocalizedStringKey {
        switch position {
        case .below: "Por debajo de la referencia general"
        case .within: "Dentro de la referencia general"
        case .above: "Por encima de la referencia general"
        }
    }
}

/// Seguimiento de presión arterial, glucemia, lípidos, peso y otros resultados.
struct LabResultsView: View {
    @State private var editing: LabResult?
    private var store: LabResultStore { .shared }

    private var kinds: [LabResult.Kind] {
        LabResult.Kind.allCases.filter { kind in store.results.contains { $0.kind == kind } }
    }

    var body: some View {
        List {
            Section {
                Button {
                    editing = LabResult(kind: .systolicPressure, date: .now, value: 120)
                } label: {
                    Label("Agregar un resultado", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Presión arterial, glucemia, HbA1c, colesterol total, LDL, HDL, triglicéridos, peso u otro resultado de laboratorio. Se muestran con su unidad, su fecha y una referencia general para adultos con su fuente. No es un diagnóstico: los valores objetivo dependen de tu riesgo y los define tu médico. Estos datos no cambian ninguna puntuación de HÅLSYN.")
            }
            ForEach(kinds) { kind in
                Section {
                    LabKindSection(kind: kind, results: store.results.series(kind)) { editing = $0 }
                } header: {
                    Text(LocalizedStringKey(kind.title))
                }
            }
        }
        .navigationTitle("Salud cardiometabólica")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { result in
            NavigationStack {
                LabResultEditor(result: result)
            }
        }
    }
}

private struct LabKindSection: View {
    let kind: LabResult.Kind
    let results: [LabResult]
    let edit: (LabResult) -> Void

    var body: some View {
        let reference = LabReference.general(kind, sex: ReferenceProfileStore.shared.sex)
        if results.count >= 2, kind != .other {
            Chart {
                if let reference, let upper = reference.upper {
                    RuleMark(y: .value("Referencia", upper))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.halsynSecondaryText.opacity(0.6))
                }
                if let reference, let lower = reference.lower {
                    RuleMark(y: .value("Referencia", lower))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.halsynSecondaryText.opacity(0.6))
                }
                ForEach(results) { item in
                    LineMark(x: .value("Fecha", item.date, unit: .day), y: .value("Valor", item.value))
                        .foregroundStyle(Color.halsynChart)
                    PointMark(x: .value("Fecha", item.date, unit: .day), y: .value("Valor", item.value))
                        .foregroundStyle(Color.halsynChart)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 140)
        }
        if let reference {
            let summaryText = String(localized: String.LocalizationValue(reference.summary))
            Text("Referencia general: \(summaryText) · \(reference.source)")
                .font(.caption2)
                .foregroundStyle(.halsynSecondaryText)
        }
        ForEach(Array(results.reversed())) { item in
            Button {
                edit(item)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: LabText.title(item))
                            .font(.halsynCaption.weight(.semibold))
                            .foregroundStyle(.halsynPrimaryText)
                        Text(item.date, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                        if let reference {
                            Text(LabText.position(reference.position(item.value)))
                                .font(.caption2)
                                .foregroundStyle(.halsynSecondaryText)
                        }
                    }
                    Spacer()
                    Text(verbatim: LabText.value(item))
                        .font(.halsynCaption.monospacedDigit())
                        .foregroundStyle(.halsynPrimaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button("Borrar", role: .destructive) { LabResultStore.shared.remove(item.id) }
            }
        }
    }
}

struct LabResultEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var result: LabResult
    @State private var text: String
    @State private var usesAlternative = false

    init(result: LabResult) {
        _result = State(initialValue: result)
        _text = State(initialValue: HalsynFormat.decimal(result.value, fractionDigits: 1))
    }

    private var parsed: Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    /// Valor en la unidad canónica.
    private var canonical: Double? {
        guard let parsed else { return nil }
        if usesAlternative, let alternative = result.kind.alternative { return parsed * alternative.factor }
        return parsed
    }

    var body: some View {
        Form {
            Section {
                Picker("Tipo", selection: $result.kind) {
                    ForEach(LabResult.Kind.allCases) { kind in
                        Text(LocalizedStringKey(kind.title)).tag(kind)
                    }
                }
                .onChange(of: result.kind) { _, _ in usesAlternative = false }
                if result.kind == .other {
                    TextField("Nombre (p. ej. ferritina)", text: Binding(get: { result.customName ?? "" }, set: { result.customName = $0 }))
                    TextField("Unidad (p. ej. ng/mL)", text: Binding(get: { result.customUnit ?? "" }, set: { result.customUnit = $0 }))
                }
                DatePicker("Fecha", selection: $result.date, in: ...Date.now, displayedComponents: .date)
            }
            Section {
                HStack {
                    TextField("Valor", text: $text)
                        .keyboardType(.decimalPad)
                    Text(verbatim: usesAlternative ? (result.kind.alternative?.unit ?? "") : result.unit)
                        .foregroundStyle(.halsynSecondaryText)
                }
                if let alternative = result.kind.alternative {
                    Toggle(isOn: $usesAlternative) {
                        Text("Ingresar en \(alternative.unit)")
                    }
                }
                if let canonical, !result.kind.plausibleRange.contains(canonical) {
                    Label("Valor fuera de lo posible: revisa la unidad.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.halsynCaution)
                }
            }
            Section("Nota") {
                TextField("Opcional (laboratorio, en ayunas…)", text: Binding(get: { result.note ?? "" }, set: { result.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
            }
        }
        .navigationTitle("Resultado")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    guard let canonical else { return }
                    var saved = result
                    saved.value = canonical
                    LabResultStore.shared.save(saved)
                    dismiss()
                }
                .disabled(canonical.map { !result.kind.plausibleRange.contains($0) } ?? true)
            }
        }
    }
}
