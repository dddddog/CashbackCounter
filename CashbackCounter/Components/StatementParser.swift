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
        let statementDate = extractStatementDate(from: fullText)
        let transactions = parseTransactions(from: lines, statementDate: statementDate)

        return StatementMetadata(
            totalBalance: totalBalance,
            transactions: transactions,
            statementText: fullText
        )
    }

    private func parseTransactions(from lines: [String], statementDate: Date?) -> [ImportedTransaction] {
        var results: [ImportedTransaction] = []
        var currentBlock: [String] = []

        for line in lines {
            if isTransactionStart(line, statementDate: statementDate) {
                if let transaction = parseTransactionBlock(currentBlock, statementDate: statementDate) {
                    results.append(transaction)
                }
                currentBlock = [line]
            } else if !currentBlock.isEmpty {
                currentBlock.append(line)
            }
        }

        if let transaction = parseTransactionBlock(currentBlock, statementDate: statementDate) {
            results.append(transaction)
        }

        return results
    }

    private func parseTransactionBlock(
        _ blockLines: [String],
        statementDate: Date?
    ) -> ImportedTransaction? {
        guard !blockLines.isEmpty else { return nil }
        let rawText = blockLines.joined(separator: "\n")
        var buffer = ""

        for line in blockLines {
            buffer = buffer.isEmpty ? line : buffer + " " + line
            if let transaction = parseTransactionLine(buffer, statementDate: statementDate) {
                return applyRawText(rawText, to: transaction)
            }
        }

        return nil
    }

    private func parseTransactionLine(_ line: String, statementDate: Date?) -> ImportedTransaction? {
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 4 else { return nil }

        guard let (postDate, indexAfterPost) = consumeDate(from: tokens, startingAt: 0, statementDate: statementDate),
              let (transactionDate, indexAfterTransaction) = consumeDate(from: tokens, startingAt: indexAfterPost, statementDate: statementDate) else {
            return nil
        }

        var nextIndex = indexAfterTransaction
        if let (duplicatePost, dupIndex) = consumeDate(from: tokens, startingAt: nextIndex, statementDate: statementDate),
           let (duplicateTransaction, dupIndex2) = consumeDate(from: tokens, startingAt: dupIndex, statementDate: statementDate) {
            let calendar = Calendar.current
            let dupMatchesPost = calendar.isDate(duplicatePost, inSameDayAs: postDate)
            let dupMatchesTransaction = calendar.isDate(duplicatePost, inSameDayAs: transactionDate)
            let dupSecondMatchesPost = calendar.isDate(duplicateTransaction, inSameDayAs: postDate)
            let dupSecondMatchesTransaction = calendar.isDate(duplicateTransaction, inSameDayAs: transactionDate)

            if (dupMatchesPost && dupSecondMatchesTransaction) ||
                (dupMatchesTransaction && dupSecondMatchesPost) ||
                (dupMatchesPost && dupSecondMatchesPost) {
                nextIndex = dupIndex2
            }
        }

        let remainderTokens = Array(tokens.dropFirst(nextIndex))
        guard let parsed = splitAmounts(from: remainderTokens) else { return nil }
        guard let billingAmount = parsed.amounts.last else { return nil }

        let cleanedDescription = parsed.description.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !cleanedDescription.isEmpty else { return nil }
        guard !shouldIgnoreTransaction(cleanedDescription) else { return nil }

        let extracted = extractForeignDetails(from: cleanedDescription)
        var merchant = extracted.merchant
        var foreignAmount = extracted.amount
        let foreignCurrency = extracted.currency

        if foreignAmount == nil {
            if parsed.amounts.count >= 2 {
                foreignAmount = parsed.amounts[parsed.amounts.count - 2]
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
            billingAmount: billingAmount,
            foreignAmount: foreignAmount,
            foreignCurrency: foreignCurrency
        )
    }

    private func isTransactionStart(_ line: String, statementDate: Date?) -> Bool {
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2 else { return false }
        guard let (_, indexAfterPost) = consumeDate(from: tokens, startingAt: 0, statementDate: statementDate) else { return false }
        guard consumeDate(from: tokens, startingAt: indexAfterPost, statementDate: statementDate) != nil else { return false }
        return true
    }

    private func extractStatementDate(from text: String) -> Date? {
        let lines = text.components(separatedBy: .newlines)
        let datePattern = regex("(\\d{1,2}\\s*[A-Za-z]{3}\\s*\\d{2,4}|\\d{1,2}[A-Za-z]{3}\\d{2,4}|\\d{1,2}\\/\\d{1,2}\\/\\d{2,4}|\\d{4}-\\d{1,2}-\\d{1,2})")

        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("statement date") else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = datePattern.matches(in: line, range: range)
            for match in matches {
                guard let candidate = rangeString(match.range(at: 1), in: line) else { continue }
                if let date = parseDateToken(candidate, statementDate: nil) {
                    return date
                }
            }
        }

        return nil
    }

    private func consumeDate(
        from tokens: [Substring],
        startingAt index: Int,
        statementDate: Date?
    ) -> (date: Date, nextIndex: Int)? {
        guard index < tokens.count else { return nil }
        let maxIndex = tokens.count - 1

        let candidates: [(String, Int)] = [
            index + 2 <= maxIndex ? (String(tokens[index]) + String(tokens[index + 1]) + String(tokens[index + 2]), 3) : ("", 0),
            index + 2 <= maxIndex ? (String(tokens[index]) + " " + String(tokens[index + 1]) + " " + String(tokens[index + 2]), 3) : ("", 0),
            index + 1 <= maxIndex ? (String(tokens[index]) + String(tokens[index + 1]), 2) : ("", 0),
            index + 1 <= maxIndex ? (String(tokens[index]) + " " + String(tokens[index + 1]), 2) : ("", 0),
            (String(tokens[index]), 1)
        ]

        for (candidate, length) in candidates where length > 0 {
            if let date = parseDateToken(candidate, statementDate: statementDate) {
                return (date: date, nextIndex: index + length)
            }
        }

        return nil
    }

    private func parseDateToken(_ token: String, statementDate: Date?) -> Date? {
        let trimmed = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        guard !trimmed.isEmpty else { return nil }

        for formatter in Self.numericDateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        let compact = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        if let date = parseMonthAbbreviationDate(compact, statementDate: statementDate) {
            return date
        }

        if let date = parseSlashDateWithoutYear(trimmed, statementDate: statementDate) {
            return date
        }

        return nil
    }

    private func parseMonthAbbreviationDate(_ token: String, statementDate: Date?) -> Date? {
        let pattern = regex("^(\\d{1,2})([A-Z]{3})(\\d{2,4})?$")
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = pattern.firstMatch(in: token, range: range), match.numberOfRanges >= 3 else { return nil }
        guard let dayString = rangeString(match.range(at: 1), in: token),
              let monthString = rangeString(match.range(at: 2), in: token) else { return nil }

        let monthMap: [String: Int] = [
            "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
            "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12
        ]
        guard let day = Int(dayString), let month = monthMap[monthString] else { return nil }

        let year: Int
        if match.numberOfRanges >= 4, let yearString = rangeString(match.range(at: 3), in: token), !yearString.isEmpty {
            year = normalizeYear(from: yearString)
        } else {
            year = inferredYear(for: month, statementDate: statementDate)
        }

        return makeDate(day: day, month: month, year: year)
    }

    private func parseSlashDateWithoutYear(_ token: String, statementDate: Date?) -> Date? {
        let parts = token.split(separator: "/")
        guard parts.count == 2 else { return nil }
        guard let first = Int(parts[0]), let second = Int(parts[1]) else { return nil }

        let day: Int
        let month: Int
        if first > 12 {
            day = first
            month = second
        } else if second > 12 {
            day = second
            month = first
        } else {
            day = first
            month = second
        }

        let year = inferredYear(for: month, statementDate: statementDate)
        return makeDate(day: day, month: month, year: year)
    }

    private func normalizeYear(from string: String) -> Int {
        if string.count == 2, let year = Int(string) {
            return 2000 + year
        }
        return Int(string) ?? Calendar.current.component(.year, from: Date())
    }

    private func inferredYear(for month: Int, statementDate: Date?) -> Int {
        let calendar = Calendar.current
        let baseYear = statementDate.map { calendar.component(.year, from: $0) } ?? calendar.component(.year, from: Date())
        guard let statementDate else { return baseYear }
        let statementMonth = calendar.component(.month, from: statementDate)
        if month - statementMonth >= 6 {
            return baseYear - 1
        }
        return baseYear
    }

    private func makeDate(day: Int, month: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        return Calendar.current.date(from: components)
    }

    private func splitAmounts(from tokens: [Substring]) -> (description: String, amounts: [Double])? {
        guard !tokens.isEmpty else { return nil }
        var amounts: [Double] = []
        var amountStartIndex: Int?
        var index = tokens.count - 1
        var pendingCredit = false

        while index >= 0 {
            let token = tokens[index]
            let upper = token.uppercased()

            if upper == "CR" || upper == "CREDIT" {
                pendingCredit = true
                index -= 1
                continue
            }

            if isCurrencyToken(token) {
                index -= 1
                continue
            }

            if let amount = parseAmountToken(token, forceNegative: pendingCredit) {
                amounts.insert(amount, at: 0)
                pendingCredit = false
                amountStartIndex = index
                index -= 1
                continue
            }

            if !amounts.isEmpty {
                break
            }
            index -= 1
        }

        guard let startIndex = amountStartIndex else { return nil }

        var descriptionTokens = Array(tokens[..<startIndex])
        while let last = descriptionTokens.last, isCurrencyToken(last) {
            descriptionTokens.removeLast()
        }
        let description = descriptionTokens.joined(separator: " ")
        return (description: description, amounts: amounts)
    }

    private func isCurrencyToken(_ token: Substring) -> Bool {
        let upper = token.uppercased()
        let currencies = ["HKD", "USD", "SGD", "JPY", "CNY", "RMB", "EUR", "GBP", "AUD", "CAD", "TWD", "$", "HK$", "US$"]
        return currencies.contains(upper)
    }

    private func parseAmountToken(_ token: Substring, forceNegative: Bool) -> Double? {
        guard let parsed = parseAmount(String(token)) else { return nil }
        return forceNegative ? -abs(parsed) : parsed
    }

    private func shouldIgnoreTransaction(_ description: String) -> Bool {
        let upper = description.uppercased()
        let ignoreKeywords = ["PREVIOUS BALANCE", "BALANCE FORWARD"]
        return ignoreKeywords.contains(where: { upper.contains($0) })
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
        let trailingRegex = regex("^(.*?)(?:\\s+)(" + amountPattern + ")$")
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
        let amountRegex = regex(amountPattern)
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
        let amountRegex = regex(amountPattern)
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
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var isNegative = false

        let upper = text.uppercased()
        if upper.contains("CR") {
            isNegative = true
            text = text.replacingOccurrences(of: "CR", with: "", options: .caseInsensitive)
        }

        if text.contains("(") && text.contains(")") {
            isNegative = true
            text = text.replacingOccurrences(of: "(", with: "")
            text = text.replacingOccurrences(of: ")", with: "")
        }

        if text.hasPrefix("-") {
            isNegative = true
            text.removeFirst()
        }

        text = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "HK$", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "US$", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "$", with: "")

        let filtered = text.filter { $0.isNumber || $0 == "." }
        guard let value = Double(filtered) else { return nil }
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

    private static let numericDateFormatters: [DateFormatter] = {
        let formats = ["MM/dd/yy", "MM/dd/yyyy", "dd/MM/yy", "dd/MM/yyyy", "yyyy-MM-dd"]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            return formatter
        }
    }()

    private let amountPattern = "-?[A-Za-z$]{0,4}\\s*\\(?[\\d,]+\\.\\d{2}\\)?(?:[cC][rR])?"
}
