import HalsynCore
import HalsynDesign
import SwiftUI

/// Reúne los indicadores que ya calcula HÅLSYN para el estado de entrenamiento.
@MainActor
enum TrainingStatusBuilder {
    static func build(runs: [WorkoutSummary], provider: any HealthDataProviding, reloadKey: String) async -> TrainingStatus {
        let calendar = Calendar.current
        let now = Date.now
        var inputs = TrainingStatusInputs()
        let onlyRuns = runs.filter(\.activity.isRun)
        let start28 = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let start14 = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        inputs.runsLast28 = onlyRuns.filter { $0.start >= start28 }.count

        // Ritmo a pulso fijo (el pulso elegido en Capacidad aeróbica).
        let target = UserDefaults.standard.object(forKey: "halsyn.aerobic.heartRate") as? Double ?? 150
        if case let .success(trend) = AerobicAnalysis.trend(at: target, observations: AerobicStore.shared.valid, today: now, calendar: calendar) {
            inputs.aerobicVerdict = trend.verdict
        }

        // VDOT de hoy frente al de hace 4 semanas, con su incertidumbre.
        let fitness = FitnessStore.shared
        if let current = fitness.performance(runs: onlyRuns, today: now),
           let previous = fitness.performance(runs: onlyRuns.filter { $0.start <= start28 }, today: start28) {
            let change = current.currentVDOT - previous.currentVDOT
            inputs.vdotChange = change
            inputs.vdotChangeIsClear = abs(change) > 1.96 * (current.uncertainty * current.uncertainty + previous.uncertainty * previous.uncertainty).squareRoot()
        }

        // Carga por pulso: la misma que muestra «Carga y forma».
        let store = TrainingLoadStore.shared
        let settings = RunSettingsStore.shared.settings
        let sex = ReferenceProfileStore.shared.sex?.rawValue ?? "-"
        let key = "\(reloadKey)|\(LoadMetric.heartRate.rawValue)|0|\(settings.zones.hashValue)|\(settings.rideZones?.hashValue ?? 0)|\(sex)"  // nolocalize
        await store.load(.heartRate, provider: provider, settings: settings, ftp: nil, key: key)
        inputs.loadRatio = store.summary(.heartRate, key: key)?.ratio

        // Intensidad de las últimas 2 semanas (tiempo) y rodajes suaves hechos intensos.
        let recent = onlyRuns.filter { $0.start >= start14 }
        let intensities = IntensityContext.intensities(recent)
        var classified = 0.0, hard = 0.0
        for run in recent {
            guard let intensity = intensities[run.id], intensity.kind != .unknown else { continue }
            classified += run.duration
            if intensity.kind >= .moderate { hard += run.duration }
            if let type = intensity.sessionType, type == .easy || type == .long || type == .recovery {
                inputs.easySessions += 1
                if intensity.harderThanPlanned { inputs.harderThanPlanned += 1 }
            }
        }
        if classified > 0 { inputs.hardShare = hard / classified }

        // Recuperación de los últimos 7 días: días con cada señal peor que tu basal.
        let estimates = await provider.recoveryEstimates(endingOn: now, days: 7)
        func adverseDays(_ kind: RecoveryComponentKind) -> Int? {
            let components = estimates.compactMap { $0.components.first { $0.kind == kind && $0.score != nil } }
            return components.isEmpty ? nil : components.filter { $0.impact == .negative }.count
        }
        inputs.hrvLowDays = adverseDays(.heartRateVariability)
        inputs.restingHighDays = adverseDays(.restingHeartRate)
        inputs.shortSleepDays = adverseDays(.sleep)
        return TrainingStatusEngine.evaluate(inputs, date: now)
    }
}

enum TrainingStatusText {
    static func title(_ state: TrainingStatus.State) -> String {
        switch state {
        case .productive: String(localized: "Productivo")
        case .maintaining: String(localized: "Mantenimiento")
        case .recoveryNeeded: String(localized: "Recuperación necesaria")
        case .highLoad: String(localized: "Carga elevada")
        case .uncertain: String(localized: "Progreso incierto")
        case .insufficientData: String(localized: "Datos insuficientes")
        }
    }

    static func summary(_ state: TrainingStatus.State) -> String {
        switch state {
        case .productive: String(localized: "Mejoras con una carga que puedes sostener.")
        case .maintaining: String(localized: "Carga habitual y sin un cambio claro de forma: mantienes lo que tienes.")
        case .recoveryNeeded: String(localized: "Varias señales de recuperación están peor que tu basal: conviene aflojar unos días.")
        case .highLoad: String(localized: "Esta semana la carga subió mucho frente a tu habitual.")
        case .uncertain: String(localized: "Las señales no van en la misma dirección o la forma va a menos.")
        case .insufficientData: String(localized: "Pocas carreras recientes para decir algo con sentido.")
        }
    }

    static func color(_ state: TrainingStatus.State) -> Color {
        switch state {
        case .productive: .halsynPositive
        case .maintaining, .insufficientData: .halsynSecondaryText
        case .recoveryNeeded, .highLoad, .uncertain: .halsynCaution
        }
    }

    static func confidence(_ confidence: TrainingStatus.Confidence) -> String {
        switch confidence {
        case .high: String(localized: "Confianza alta")
        case .medium: String(localized: "Confianza media")
        case .low: String(localized: "Confianza baja: faltan datos")
        }
    }

    static func signal(_ signal: TrainingStatus.Signal) -> String {
        switch signal {
        case let .aerobic(verdict):
            switch verdict {
            case .faster: return String(localized: "Corres más rápido con el mismo pulso que hace 8 semanas.")
            case .slower: return String(localized: "Corres más lento con el mismo pulso que hace 8 semanas.")
            case .unclear: return String(localized: "El ritmo a pulso fijo no cambió de forma clara en 8 semanas.")
            }
        case let .vdot(change, isClear):
            let changeText = (change >= 0 ? "+" : "−") + HalsynFormat.decimal(abs(change), fractionDigits: 1)  // nolocalize
            return isClear
                ? String(localized: "VDOT \(changeText) en 4 semanas, más allá de su incertidumbre.")
                : String(localized: "VDOT \(changeText) en 4 semanas, dentro de su incertidumbre.")
        case let .load(ratio):
            let ratioText = HalsynFormat.decimal(ratio, fractionDigits: 1) + "×"  // nolocalize
            if ratio > TrainingStatusEngine.highLoadRatio { return String(localized: "Carga de 7 días: \(ratioText) tu media semanal anterior (sube rápido).") }
            if ratio < TrainingStatusEngine.lowLoadRatio { return String(localized: "Carga de 7 días: \(ratioText) tu media semanal anterior (semana más liviana).") }
            return String(localized: "Carga de 7 días: \(ratioText) tu media semanal anterior (en tu rango).")
        case let .intensity(share):
            let percent = String(Int((share * 100).rounded()))
            return share > TrainingStatusEngine.maximumHardShare
                ? String(localized: "\(percent) % del tiempo de carrera fue moderado o intenso en 2 semanas (la referencia ronda el 20 %).")
                : String(localized: "\(percent) % del tiempo de carrera fue moderado o intenso en 2 semanas: buena base suave.")
        case let .easyRunsTooHard(count, total):
            let countText = String(count), totalText = String(total)
            return String(localized: "\(countText) de \(totalText) rodajes suaves fueron más intensos de lo previsto.")
        case let .hrv(days):
            let daysText = String(days)
            return String(localized: "HRV por debajo de tu basal \(daysText) de los últimos 7 días.")
        case let .restingHeartRate(days):
            let daysText = String(days)
            return String(localized: "FC en reposo por encima de tu basal \(daysText) de los últimos 7 días.")
        case let .sleep(days):
            let daysText = String(days)
            return String(localized: "Sueño por debajo de lo habitual \(daysText) de las últimas 7 noches.")
        case let .consistency(runs):
            let runsText = String(runs)
            return String(localized: "\(runsText) carreras en las últimas 4 semanas.")
        }
    }

    static func missing(_ key: String) -> String {
        switch key {
        case "aerobic": String(localized: "ritmo a pulso fijo")
        case "vdot": String(localized: "evolución del VDOT")
        case "load": String(localized: "carga")
        case "intensity": String(localized: "intensidad")
        case "hrv": String(localized: "HRV")
        case "restingHeartRate": String(localized: "FC en reposo")
        default: String(localized: "sueño")
        }
    }
}

/// Tarjeta de arriba de Rendimiento.
struct TrainingStatusCard: View {
    let status: TrainingStatus

    var body: some View {
        NavigationLink {
            TrainingStatusView(status: status)
        } label: {
            HalsynCard {
                VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                    HStack {
                        Text("Estado de entrenamiento")
                            .halsynEyebrowStyle()
                        Spacer()
                        Text(verbatim: TrainingStatusText.confidence(status.confidence))
                            .font(.caption2)
                            .foregroundStyle(.halsynSecondaryText)
                    }
                    Text(verbatim: TrainingStatusText.title(status.state))
                        .font(.halsynTitle)
                        .foregroundStyle(TrainingStatusText.color(status.state))
                    Text(verbatim: TrainingStatusText.summary(status.state))
                        .font(.halsynCaption)
                        .foregroundStyle(.halsynSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Por qué")
                            .font(.halsynCaption.weight(.semibold))
                            .foregroundStyle(.halsynAccentText)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.halsynAccentText)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// El porqué del estado: a favor, en contra, lo que falta.
struct TrainingStatusView: View {
    let status: TrainingStatus

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Estado"), value: TrainingStatusText.title(status.state))
                LabeledContent(String(localized: "Confianza"), value: TrainingStatusText.confidence(status.confidence))
                LabeledContent(String(localized: "Actualizado"), value: status.date.formatted(date: .abbreviated, time: .shortened))
            } footer: {
                Text(verbatim: TrainingStatusText.summary(status.state))
            }
            if !status.supporting.isEmpty {
                Section("Lo respalda") {
                    ForEach(Array(status.supporting.enumerated()), id: \.offset) { _, signal in
                        Label(TrainingStatusText.signal(signal), systemImage: "checkmark.circle")
                            .font(.halsynCaption)
                    }
                }
            }
            if !status.contradicting.isEmpty {
                Section(status.state == .uncertain || status.state == .insufficientData ? LocalizedStringKey("Señales") : LocalizedStringKey("Va en contra")) {
                    ForEach(Array(status.contradicting.enumerated()), id: \.offset) { _, signal in
                        Label(TrainingStatusText.signal(signal), systemImage: signal.tone == .positive ? "arrow.up.circle" : "exclamationmark.circle")
                            .font(.halsynCaption)
                            .foregroundStyle(signal.tone == .negative ? Color.halsynCaution : Color.halsynPrimaryText)
                    }
                }
            }
            if !status.missing.isEmpty {
                Section {
                    Text(verbatim: status.missing.map(TrainingStatusText.missing).joined(separator: ", "))
                        .font(.halsynCaption)
                } header: {
                    Text("Sin datos (bajan la confianza)")
                }
            }
            Section {
                Text("Reglas, en orden: con 2 o más señales de recuperación peores que tu basal (HRV, FC en reposo, sueño) → recuperación necesaria. Si la carga de 7 días supera 1,3 veces tu media semanal anterior → carga elevada (describe el cambio de carga, no predice lesiones). Si la forma va a menos o las tendencias se contradicen → progreso incierto. Con una mejora clara (ritmo a pulso fijo o VDOT) → productivo. Si no, mantenimiento. Ninguna métrica sola decide. Es orientativo, no un diagnóstico.")
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                Text(verbatim: "TrainingStatusEngine \(TrainingStatusEngine.version)")  // nolocalize
                    .font(.caption2.monospaced())
                    .foregroundStyle(.halsynSecondaryText)
            }
        }
        .navigationTitle("Estado de entrenamiento")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .halsynScreenBackground()
    }
}
