import Foundation

/// Lightweight Open-Meteo client. Free, no API key, no SDK — just a GET.
/// We fetch hourly temps + weather codes for the requested day, then pick
/// the hour matching the session start so the card shows what it'll
/// actually be like at tip-off.
@MainActor
final class WeatherService: ObservableObject {
    struct Forecast: Equatable {
        let temperatureF: Int
        let conditionLabel: String
        let symbol: String
        let isOutdoorish: Bool
    }

    /// Cache by (lat, lon, day) so re-rendering the home tab doesn't
    /// re-fetch every time. Open-Meteo is unmetered but politeness still
    /// matters and the cache means the chip paints instantly.
    private var cache: [String: Forecast] = [:]

    func forecast(for session: GameSession) async -> Forecast? {
        guard let lat = session.latitude,
              let lon = session.longitude,
              let target = session.sessionDateTime else { return nil }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        let dayString = dayFormatter.string(from: target)

        let key = "\(lat),\(lon),\(dayString)"
        if let hit = cache[key] { return hit }

        // Open-Meteo: hourly fetch for the session day.
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(lat)"),
            URLQueryItem(name: "longitude", value: "\(lon)"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weathercode"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "America/Los_Angeles"),
            URLQueryItem(name: "start_date", value: dayString),
            URLQueryItem(name: "end_date", value: dayString),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            guard let hourly = decoded.hourly,
                  let times = hourly.time,
                  let temps = hourly.temperature_2m,
                  let codes = hourly.weathercode else { return nil }

            // Find the hour closest to session start.
            let hourFormatter = DateFormatter()
            hourFormatter.dateFormat = "yyyy-MM-dd'T'HH:00"
            hourFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
            let targetString = hourFormatter.string(from: target)
            let idx = times.firstIndex(of: targetString)
                ?? times.firstIndex(where: { $0.hasPrefix(dayString + "T18") })
                ?? 0
            guard idx < temps.count, idx < codes.count else { return nil }

            let (label, symbol, outdoorish) = Self.describe(code: codes[idx])
            let forecast = Forecast(
                temperatureF: Int(temps[idx].rounded()),
                conditionLabel: label,
                symbol: symbol,
                isOutdoorish: outdoorish
            )
            cache[key] = forecast
            return forecast
        } catch {
            return nil
        }
    }

    /// WMO weather code → human label + SF Symbol.
    /// https://open-meteo.com/en/docs#weathervariables
    private static func describe(code: Int) -> (String, String, Bool) {
        switch code {
        case 0: return ("Clear", "sun.max.fill", true)
        case 1, 2: return ("Mostly clear", "cloud.sun.fill", true)
        case 3: return ("Overcast", "cloud.fill", true)
        case 45, 48: return ("Foggy", "cloud.fog.fill", true)
        case 51, 53, 55, 56, 57: return ("Drizzle", "cloud.drizzle.fill", false)
        case 61, 63, 65, 66, 67, 80, 81, 82: return ("Rainy", "cloud.rain.fill", false)
        case 71, 73, 75, 77, 85, 86: return ("Snow", "cloud.snow.fill", false)
        case 95, 96, 99: return ("Thunderstorms", "cloud.bolt.rain.fill", false)
        default: return ("Mild", "cloud.fill", true)
        }
    }

    private struct OpenMeteoResponse: Decodable {
        let hourly: Hourly?
        struct Hourly: Decodable {
            let time: [String]?
            let temperature_2m: [Double]?
            let weathercode: [Int]?
        }
    }
}
