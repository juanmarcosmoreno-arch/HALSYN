import CoreLocation
import HalsynCore
import HalsynDesign
import SwiftUI
import WeatherKit

/// Tiempo de las carreras grabadas sin él (las de HÅLSYN): se consulta a
/// WeatherKit para la hora de salida y el punto de salida redondeado a unos
/// 1 km, y se guarda en este iPhone para no volver a pedirlo.
@MainActor
enum RunWeatherLookup {
    static let cacheKey = "halsyn.weatherCache"

    static func cached(_ id: UUID) -> RunWeather? {
        cache()[id.uuidString]
    }

    static func weather(for workout: WorkoutSummary, start location: LocationSample) async -> RunWeather? {
        if let cached = cached(workout.id) { return cached }
        // Redondeado: el tiempo no cambia en un kilómetro y no se envía la ubicación exacta.
        let place = CLLocation(latitude: (location.latitude * 100).rounded() / 100, longitude: (location.longitude * 100).rounded() / 100)
        let start = workout.start.addingTimeInterval(-3600)
        let end = workout.start.addingTimeInterval(3600)
        guard let forecast = try? await WeatherService.shared.weather(for: place, including: .hourly(startDate: start, endDate: end)),
              let hour = forecast.forecast.min(by: { abs($0.date.timeIntervalSince(workout.start)) < abs($1.date.timeIntervalSince(workout.start)) })
        else { return nil }
        let weather = RunWeather(
            temperature: hour.temperature.converted(to: .celsius).value,
            humidity: hour.humidity,
            source: .weatherKit
        )
        var all = cache()
        all[workout.id.uuidString] = weather
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: cacheKey) }
        return weather
    }

    private static func cache() -> [String: RunWeather] {
        UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode([String: RunWeather].self, from: $0) } ?? [:]
    }
}

/// Clima de la carrera y qué significa para el ritmo y el pulso.
struct RunWeatherCard: View {
    let weather: RunWeather
    let unitSystem: UnitSystem
    @State private var attribution: WeatherAttribution?

    var body: some View {
        HalsynCard {
            VStack(alignment: .leading, spacing: HalsynSpacing.s) {
                HalsynSectionHeader("Clima", eyebrow: HalsynModule.spring.brandName)
                HStack(spacing: HalsynSpacing.l) {
                    Label(temperatureText, systemImage: "thermometer.medium")
                        .font(.halsynHeadline.monospacedDigit())
                    if let humidity = weather.humidity {
                        Label {
                            HStack(spacing: 4) {
                                Text(verbatim: "\(Int((humidity * 100).rounded())) %")
                                Text("humedad")
                            }
                        } icon: {
                            Image(systemName: "humidity")
                        }
                        .font(.halsynHeadline.monospacedDigit())
                    }
                }
                .foregroundStyle(.halsynPrimaryText)
                Text(LocalizedStringKey(weather.heat.title))
                    .font(.halsynBody.weight(.semibold))
                    .foregroundStyle(weather.heat >= .warm ? Color.halsynCaution : Color.halsynAccentText)
                ExpandableText(LocalizedStringKey(weather.heat.explanation))
                    .font(.halsynCaption)
                    .foregroundStyle(.halsynSecondaryText)
                ReferenceLinks(references: [ScienceReferences.weatherMarathon])
                if weather.source == .weatherKit {
                    // Atribución que exige WeatherKit.
                    Text("Consultado con la hora y el punto de salida aproximado (unos 1 km).")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                    HStack(spacing: 4) {
                        Text(verbatim: " Weather")
                        if let url = attribution?.legalPageURL {
                            Link(destination: url) {
                                Text("Fuentes de datos")
                            }
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.halsynSecondaryText)
                } else {
                    Text("Guardado con el entrenamiento en Salud.")
                        .font(.caption2)
                        .foregroundStyle(.halsynSecondaryText)
                }
            }
        }
        .task {
            if weather.source == .weatherKit {
                attribution = try? await WeatherService.shared.attribution
            }
        }
    }

    private var temperatureText: String {
        if unitSystem == .imperial {
            return "\(HalsynFormat.integer(weather.temperature * 9 / 5 + 32)) °F"
        }
        return "\(HalsynFormat.integer(weather.temperature)) °C"
    }
}
