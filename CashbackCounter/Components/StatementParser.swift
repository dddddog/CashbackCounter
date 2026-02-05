import Foundation
import PDFKit

struct StatementMetadata {
    let totalBalance: Double?
    let transactions: [ImportedTransaction]
    let statementText: String?
    let cardLast4: String?
    let cardName: String?

    init(
        totalBalance: Double?,
        transactions: [ImportedTransaction],
        statementText: String? = nil,
        cardLast4: String? = nil,
        cardName: String? = nil
    ) {
        self.totalBalance = totalBalance
        self.transactions = transactions
        self.statementText = statementText
        self.cardLast4 = cardLast4
        self.cardName = cardName
    }
}

struct ImportedTransaction: Identifiable, Hashable {
    let id: UUID
    let transactionDate: Date
    let postDate: Date
    let merchant: String
    let billingAmount: Double
    let foreignAmount: Double?
    let foreignCurrency: String?
    let region: Region?
    let paymentMethod: PaymentMethod?
    let category: Category?
    let rawText: String?

    init(
        id: UUID = UUID(),
        transactionDate: Date,
        postDate: Date,
        merchant: String,
        billingAmount: Double,
        foreignAmount: Double? = nil,
        foreignCurrency: String? = nil,
        region: Region? = nil,
        paymentMethod: PaymentMethod? = nil,
        category: Category? = nil,
        rawText: String? = nil
    ) {
        self.id = id
        self.transactionDate = transactionDate
        self.postDate = postDate
        self.merchant = merchant
        self.billingAmount = billingAmount
        self.foreignAmount = foreignAmount
        self.foreignCurrency = foreignCurrency
        self.region = region
        self.paymentMethod = paymentMethod
        self.category = category
        self.rawText = rawText
    }
}

struct StatementParser {
    func parse(from url: URL) -> StatementMetadata? {
        guard let document = PDFDocument(url: url) else { return nil }

        var pageTexts: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            guard let text = page.string, !text.isEmpty else { continue }
            pageTexts.append(text)
        }

        let fullText = pageTexts.joined(separator: "\n")
        let lines = fullText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let totalBalance = extractTotalBalance(from: fullText)
        let transactions = parseTransactions(from: lines)

        return StatementMetadata(
            totalBalance: totalBalance,
            transactions: transactions,
            statementText: fullText
        )
    }

    private func parseTransactions(from lines: [String]) -> [ImportedTransaction] {
        var results: [ImportedTransaction] = []
        var currentBlock: [String] = []

        let startRegex = regex("^(\\d{2}\\/\\d{2}\\/\\d{2})\\s+(\\d{2}\\/\\d{2}\\/\\d{2})\\b")
        let fullRegex = regex("^(\\d{2}\\/\\d{2}\\/\\d{2})\\s+(\\d{2}\\/\\d{2}\\/\\d{2})\\s+(.+?)\\s+(-?\\$?\\(?[\\d,]+\\.\\d{2}\\)?)$")
        let fullDoubleRegex = regex("^(\\d{2}\\/\\d{2}\\/\\d{2})\\s+(\\d{2}\\/\\d{2}\\/\\d{2})\\s+(.+?)\\s+(-?\\$?\\(?[\\d,]+\\.\\d{2}\\)?)\\s+(-?\\$?\\(?[\\d,]+\\.\\d{2}\\)?)$")

        for line in lines {
            if matches(startRegex, in: line) {
                if let transaction = parseTransactionBlock(currentBlock, fullRegex: fullRegex, extendedRegex: fullDoubleRegex) {
                    results.append(transaction)
                }
                currentBlock = [line]
            } else if !currentBlock.isEmpty {
                currentBlock.append(line)
            }
        }

        if let transaction = parseTransactionBlock(currentBlock, fullRegex: fullRegex, extendedRegex: fullDoubleRegex) {
            results.append(transaction)
        }

        return results
    }

    private func parseTransactionBlock(
        _ blockLines: [String],
        fullRegex: NSRegularExpression,
        extendedRegex: NSRegularExpression
    ) -> ImportedTransaction? {
        guard !blockLines.isEmpty else { return nil }
        let rawText = blockLines.joined(separator: "\n")
        var buffer = ""

        for line in blockLines {
            buffer = buffer.isEmpty ? line : buffer + " " + line
            if let transaction = parseTransactionLine(buffer, using: fullRegex, extendedRegex: extendedRegex) {
                return applyRawText(rawText, to: transaction)
            }
        }

        return nil
    }

    private func parseTransactionLine(_ line: String, using regex: NSRegularExpression, extendedRegex: NSRegularExpression) -> ImportedTransaction? {
        if let transaction = parseTransactionLine(line, match: extendedRegex, expectsTwoAmounts: true) {
            return transaction
        }
        return parseTransactionLine(line, match: regex, expectsTwoAmounts: false)
    }

    private func parseTransactionLine(_ line: String, match regex: NSRegularExpression, expectsTwoAmounts: Bool) -> ImportedTransaction? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        guard match.numberOfRanges == (expectsTwoAmounts ? 6 : 5) else { return nil }

        guard let transactionDateString = rangeString(match.range(at: 1), in: line),
              let postDateString = rangeString(match.range(at: 2), in: line),
              let descriptionString = rangeString(match.range(at: 3), in: line),
              let amountString = rangeString(match.range(at: 4), in: line) else {
            return nil
        }

        let secondAmountString: String?
        if expectsTwoAmounts {
            secondAmountString = rangeString(match.range(at: 5), in: line)
        } else {
            secondAmountString = nil
        }

        guard let transactionDate = Self.statementDateFormatter.date(from: transactionDateString),
              let postDate = Self.statementDateFormatter.date(from: postDateString) else {
            return nil
        }

        let transactionAmount = parseAmount(amountString)
        let billingAmount: Double?
        if let secondAmountString {
            billingAmount = parseAmount(secondAmountString)
        } else {
            billingAmount = transactionAmount
        }

        guard let finalBilling = billingAmount else { return nil }

        let cleanedDescription = descriptionString.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let extracted = extractForeignDetails(from: cleanedDescription)

        var merchant = extracted.merchant
        var foreignAmount = extracted.amount
        let foreignCurrency = extracted.currency

        if foreignAmount == nil {
            if expectsTwoAmounts, let transactionAmount {
                foreignAmount = transactionAmount
            } else if let trailing = extractTrailingAmount(from: merchant) {
                merchant = trailing.merchant
                foreignAmount = trailing.amount
            } else if let fallbackAmount = extractSecondaryAmount(from: line) {
                foreignAmount = fallbackAmount
            }
        }

        return ImportedTransaction(
            transactionDate: transactionDate,
            postDate: postDate,
            merchant: merchant,
            billingAmount: finalBilling,
            foreignAmount: foreignAmount,
            foreignCurrency: foreignCurrency
        )
    }

    private func applyRawText(_ rawText: String, to transaction: ImportedTransaction) -> ImportedTransaction {
        ImportedTransaction(
            id: transaction.id,
            transactionDate: transaction.transactionDate,
            postDate: transaction.postDate,
            merchant: transaction.merchant,
            billingAmount: transaction.billingAmount,
            foreignAmount: transaction.foreignAmount,
            foreignCurrency: transaction.foreignCurrency,
            region: transaction.region,
            paymentMethod: transaction.paymentMethod,
            category: transaction.category,
            rawText: rawText
        )
    }

    private func extractTrailingAmount(from text: String) -> (merchant: String, amount: Double)? {
        let trailingRegex = regex("^(.*?)(?:\\s+)(-?\\$?\\(?[\\d,]+\\.\\d{2}\\)?)$")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = trailingRegex.firstMatch(in: text, range: range), match.numberOfRanges == 3 else {
            return nil
        }
        guard let merchant = rangeString(match.range(at: 1), in: text),
              let amountString = rangeString(match.range(at: 2), in: text),
              let amount = parseAmount(amountString) else {
            return nil
        }
        return (merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount)
    }

    private func extractSecondaryAmount(from text: String) -> Double? {
        let amountRegex = regex("-?\\$?\\(?[\\d,]+\\.\\d{2}\\)?")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = amountRegex.matches(in: text, range: range)
        guard matches.count >= 2 else { return nil }
        let targetIndex = matches.count - 2
        guard let amountString = rangeString(matches[targetIndex].range, in: text) else { return nil }
        return parseAmount(amountString)
    }

    private func extractTotalBalance(from text: String) -> Double? {
        let keywords = ["New Balance", "Statement Balance", "Total Balance", "Balance Due", "Closing Balance"]
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            guard keywords.contains(where: { line.localizedCaseInsensitiveContains($0) }) else { continue }
            if let amount = extractFirstAmount(from: line) {
                return amount
            }
        }

        return extractFirstAmount(from: text)
    }

    private func extractFirstAmount(from text: String) -> Double? {
        let amountRegex = regex("-?\\$?\\(?[\\d,]+\\.\\d{2}\\)?")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = amountRegex.firstMatch(in: text, range: range) else { return nil }
        guard let amountString = rangeString(match.range(at: 0), in: text) else { return nil }
        return parseAmount(amountString)
    }

    private func extractForeignDetails(from description: String) -> (merchant: String, currency: String?, amount: Double?) {
        let patterns = ["([A-Z]{3})\\s*([0-9]+(?:\\.[0-9]{2})?)", "([0-9]+(?:\\.[0-9]{2})?)\\s*([A-Z]{3})"]

        for pattern in patterns {
            let detailRegex = regex(pattern)
            let range = NSRange(description.startIndex..<description.endIndex, in: description)
            guard let match = detailRegex.firstMatch(in: description, range: range), match.numberOfRanges == 3 else {
                continue
            }

            guard let first = rangeString(match.range(at: 1), in: description),
                  let second = rangeString(match.range(at: 2), in: description) else {
                continue
            }

            let currency: String
            let amountString: String
            if first.count == 3 {
                currency = first
                amountString = second
            } else {
                currency = second
                amountString = first
            }

            guard let amount = Double(amountString) else { continue }

            var merchant = description
            if let removeRange = Range(match.range(at: 0), in: description) {
                merchant.removeSubrange(removeRange)
            }
            merchant = merchant.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            return (merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), currency: currency, amount: amount)
        }

        return (merchant: description.trimmingCharacters(in: .whitespacesAndNewlines), currency: nil, amount: nil)
    }

    private func parseAmount(_ raw: String) -> Double? {
        var text = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        var isNegative = false

        if text.contains("(") && text.contains(")") {
            isNegative = true
            text = text.replacingOccurrences(of: "(", with: "")
            text = text.replacingOccurrences(of: ")", with: "")
        }

        if text.hasPrefix("-") {
            isNegative = true
            text.removeFirst()
        }

        guard let value = Double(text) else { return nil }
        return isNegative ? -value : value
    }

    private func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private func rangeString(_ range: NSRange, in text: String) -> String? {
        guard let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private func regex(_ pattern: String) -> NSRegularExpression {
        return (try? NSRegularExpression(pattern: pattern, options: [])) ?? (try! NSRegularExpression(pattern: "(?!)"))
    }

    private static let statementDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
