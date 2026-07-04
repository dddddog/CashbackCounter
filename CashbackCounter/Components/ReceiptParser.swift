import Foundation

@MainActor
final class ReceiptParser {

    init() {}

    // MARK: - Public Parse

    func parse(text: String) async throws -> ReceiptMetadata {

        let merchant = extractMerchant(from: text)
        let amount = extractTotalAmount(from: text)
        let currency = detectCurrency(from: text)
        let category = detectCategory(from: text)

        return ReceiptMetadata(
            merchant: merchant,
            totalAmount: amount,
            currency: currency,
            dateString: nil,
            cardLast4: nil,
            category: category
        )
    }

    // MARK: - Merchant

    private func extractMerchant(from text: String) -> String? {
        let lines = text.split(separator: "\n")
        return lines.first.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Amount (FINAL PAID)

    private func extractTotalAmount(from text: String) -> Double? {

        // 优先匹配 Total / 合计 / 实付
        let patterns = [
            "Total[: ]*([0-9]+\\.[0-9]{1,2})",
            "合计[: ]*([0-9]+\\.[0-9]{1,2})",
            "实付[: ]*([0-9]+\\.[0-9]{1,2})",
            "Amount[: ]*([0-9]+\\.[0-9]{1,2})"
        ]

        for pattern in patterns {
            if let value = matchFirstNumber(text, pattern: pattern) {
                return value
            }
        }

        // fallback：取最大金额（防 OCR 混乱）
        return extractMaxAmount(from: text)
    }

    private func extractMaxAmount(from text: String) -> Double? {
        let regex = try? NSRegularExpression(pattern: "[0-9]+\\.[0-9]{1,2}")
        let range = NSRange(text.startIndex..., in: text)

        let matches = regex?.matches(in: text, range: range) ?? []

        let values: [Double] = matches.compactMap {
            guard let r = Range($0.range, in: text) else { return nil }
            return Double(text[r])
        }

        return values.max()
    }

    // MARK: - Currency

    private func detectCurrency(from text: String) -> String? {
        if text.contains("¥") || text.contains("JPY") { return "JPY" }
        if text.contains("$") { return "USD" }
        if text.contains("€") { return "EUR" }
        return nil
    }

    // MARK: - Category (iOS16 rule-based)

    private func detectCategory(from text: String) -> ReceiptCategory {

        let lower = text.lowercased()

        if lower.contains("starbucks") ||
            lower.contains("cafe") ||
            lower.contains("restaurant") ||
            text.contains("居酒屋") ||
            text.contains("ラーメン") {
            return .dining
        }

        if lower.contains("lawson") ||
            lower.contains("familymart") ||
            lower.contains("7-eleven") {
            return .grocery
        }

        if lower.contains("uber") ||
            lower.contains("taxi") ||
            text.contains("新幹線") ||
            lower.contains("hotel") {
            return .travel
        }

        if lower.contains("apple") ||
            lower.contains("bic camera") ||
            lower.contains("yodobashi") {
            return .digital
        }

        return .other
    }

    // MARK: - Regex helper

    private func matchFirstNumber(_ text: String, pattern: String) -> Double? {
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)

        guard let match = regex?.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text)
        else { return nil }

        return Double(text[r])
    }
}
