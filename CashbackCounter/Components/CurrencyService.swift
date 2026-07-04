import Foundation

// MARK: - API Response

struct FrankfurterLatestResponse: Decodable {
    let rates: [String: Double]
}

// MARK: - Service

struct CurrencyService {

    // MARK: Cache Keys
    private static let kRatesKey = "cached_exchange_rates"
    private static let kDateKey = "last_fetch_date"
    private static let kBaseKey = "last_rates_base"

    // MARK: Public API

    static func getRates(base: String = "CNY") async -> [String: Double] {

        print("🔄 base:", base)

        // 1. check cache
        if let lastDate = UserDefaults.standard.object(forKey: kDateKey) as? Date,
           let lastBase = UserDefaults.standard.string(forKey: kBaseKey),
           lastBase == base,
           Calendar.current.isDateInToday(lastDate),
           let cached = loadLocalRates() {

            print("✅ using cache:", base)
            return cached
        }

        print("🌍 fetching remote rates:", base)

        do {
            let rates = try await fetchRemoteRates(base: base)
            saveRatesLocally(rates, base: base)
            return rates
        } catch {
            print("❌ fetch failed, fallback")

            if let cached = loadLocalRates() {
                return cached
            }

            return [base: 1.0]
        }
    }

    // MARK: Remote

    private static func fetchRemoteRates(base: String) async throws -> [String: Double] {

        let urlString =
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/\(base.lowercased()).json"

        guard let url = URL(string: urlString) else {
            return [:]
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let rates = json?[base.lowercased()] as? [String: Double] else {
            return [:]
        }

        return rates
    }

    // MARK: Save

    private static func saveRatesLocally(_ rates: [String: Double], base: String) {

        if let data = try? JSONEncoder().encode(rates) {
            UserDefaults.standard.set(data, forKey: kRatesKey)
        }

        UserDefaults.standard.set(Date(), forKey: kDateKey)
        UserDefaults.standard.set(base, forKey: kBaseKey)
    }

    // MARK: Load Cache

    private static func loadLocalRates() -> [String: Double]? {
        guard let data = UserDefaults.standard.data(forKey: kRatesKey) else {
            return nil
        }

        return try? JSONDecoder().decode([String: Double].self, from: data)
    }
}
