//
//  StatementAnalysisViewModel.swift
//  CashbackCounter
//

import SwiftUI
import SwiftData

@Observable
final class StatementAnalysisViewModel {
    // MARK: - State
    var selectedMissing: ImportedTransaction?
    var selectedCardIndex: Int? = nil
    var analyzedTransactions: [ImportedTransaction] = []
    var detectedCardLast4: String?
    var detectedCardName: String?
    var isDetectingCard = false
    var isAnalyzingTransactions = false
    var didApplyDetectedCard = false
    var didAutoAnalyze = false

    // MARK: - Computed

    func displayedTransactions(statement: StatementMetadata) -> [ImportedTransaction] {
        analyzedTransactions.isEmpty ? statement.transactions : analyzedTransactions
    }

    func report(statement: StatementMetadata, transactions: [Transaction], cards: [CreditCard]) -> ReconciliationReport {
        let card = selectedCard(cards: cards)
        let filtered: [Transaction]
        if let card {
            filtered = transactions.filter { $0.card?.id == card.id }
        } else {
            filtered = transactions
        }
        return ReconciliationEngine().compare(imported: displayedTransactions(statement: statement), existing: filtered)
    }

    func selectedCard(cards: [CreditCard]) -> CreditCard? {
        guard let selectedCardIndex, cards.indices.contains(selectedCardIndex) else { return nil }
        return cards[selectedCardIndex]
    }

    var detectedCardText: String? {
        var parts: [String] = []
        if let detectedCardName, !detectedCardName.isEmpty {
            parts.append(detectedCardName)
        }
        if let detectedCardLast4, !detectedCardLast4.isEmpty {
            parts.append("**** \(detectedCardLast4)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Card Detection

    @MainActor
    func detectStatementCardIfNeeded(statement: StatementMetadata) async {
        guard !isDetectingCard else { return }
        guard detectedCardLast4 == nil && detectedCardName == nil else { return }
        guard let statementText = statement.statementText, !statementText.isEmpty else { return }

        let promptText = statementCardPromptText(from: statementText)
        isDetectingCard = true
        defer { isDetectingCard = false }

        do {
            let metadata = try await ReceiptParser().parseStatementCard(text: promptText)
            detectedCardLast4 = metadata.cardLast4?.trimmingCharacters(in: .whitespacesAndNewlines)
            detectedCardName = metadata.cardName?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            StatementDebugLogger.log("detectStatementCardIfNeeded failed: \(error)")
        }
    }

    func applyDetectedCardSelectionIfNeeded(cards: [CreditCard]) {
        guard !didApplyDetectedCard else { return }
        guard !cards.isEmpty else { return }

        if let detectedCardLast4 {
            let cleanedLast4 = detectedCardLast4.filter { $0.isNumber }
            if let index = cards.firstIndex(where: { $0.endNum == cleanedLast4 }) {
                selectedCardIndex = index
                didApplyDetectedCard = true
                return
            }
        }

        guard let detectedCardName, !detectedCardName.isEmpty else { return }
        if let index = cards.firstIndex(where: { card in
            card.bankName.localizedCaseInsensitiveContains(detectedCardName) ||
            card.type.localizedCaseInsensitiveContains(detectedCardName)
        }) {
            selectedCardIndex = index
            didApplyDetectedCard = true
        }
    }

    // MARK: - Transaction Analysis

    @MainActor
    func analyzeTransactions(statement: StatementMetadata, existingTransactions: [Transaction], cards: [CreditCard]) async {
        guard !isAnalyzingTransactions else { return }
        guard !statement.transactions.isEmpty else { return }
        if analyzedTransactions.count == statement.transactions.count {
            didAutoAnalyze = true
            return
        }

        isAnalyzingTransactions = true
        defer { isAnalyzingTransactions = false }

        var updated: [ImportedTransaction] = []
        let parser = ReceiptParser()

        for transaction in statement.transactions {
            if let matchedTransaction = matchedTransaction(for: transaction, existingTransactions: existingTransactions) {
                let enriched = transaction.withAnalysis(
                    region: matchedTransaction.location,
                    paymentMethod: matchedTransaction.paymentMethod,
                    category: matchedTransaction.category,
                    foreignAmount: matchedTransaction.amount
                )
                updated.append(enriched)
                continue
            }

            let prompt = transactionPromptText(for: transaction, cards: cards)
            do {
                let metadata = try await parser.parseStatementTransaction(text: prompt)
                let enriched = transaction.withAnalysis(
                    region: metadata.region,
                    paymentMethod: metadata.paymentMethod,
                    category: metadata.category,
                    foreignAmount: metadata.foreignAmount
                )
                updated.append(enriched)
            } catch {
                print("Statement transaction parse failed: \(error)")
                updated.append(transaction)
            }
        }

        analyzedTransactions = updated
        didAutoAnalyze = true
    }

    @MainActor
    func autoAnalyzeIfNeeded(statement: StatementMetadata, existingTransactions: [Transaction], cards: [CreditCard]) async {
        guard !didAutoAnalyze else { return }
        await analyzeTransactions(statement: statement, existingTransactions: existingTransactions, cards: cards)
    }

    // MARK: - Private Helpers

    private func matchedTransaction(for imported: ImportedTransaction, existingTransactions: [Transaction]) -> Transaction? {
        let calendar = Calendar.current
        return existingTransactions.first { transaction in
            amountsMatch(imported.billingAmount, transaction.billingAmount) &&
            datesWithinRange(imported.transactionDate, transaction.date, calendar: calendar)
        }
    }

    private func amountsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.0001
    }

    private func datesWithinRange(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        let leftDay = calendar.startOfDay(for: lhs)
        let rightDay = calendar.startOfDay(for: rhs)
        let dayDiff = calendar.dateComponents([.day], from: leftDay, to: rightDay).day ?? Int.max
        return abs(dayDiff) <= 3
    }

    private func transactionPromptText(for transaction: ImportedTransaction, cards: [CreditCard]) -> String {
        let card = selectedCard(cards: cards)
        let currencyCode = card?.issueRegion.currencyCode ?? "unknown"
        var lines: [String] = [
            "Merchant: \(transaction.merchant)",
            "BillingAmount: \(String(format: "%.2f", transaction.billingAmount)) \(currencyCode)",
            "BillingCurrency: \(currencyCode)"
        ]

        if let currency = transaction.region?.currencyCode, let amount = transaction.foreignAmount {
            lines.append("Foreign: \(currency) \(String(format: "%.2f", amount))")
        }

        if let rawText = transaction.rawText, !rawText.isEmpty {
            var trimmed = rawText
            let maxChars = 1200
            if trimmed.count > maxChars {
                trimmed = String(trimmed.prefix(maxChars))
            }
            lines.append("Statement block:\n\(trimmed)")
        }

        return lines.joined(separator: "\n")
    }

    private func statementCardPromptText(from fullText: String) -> String {
        let lines = fullText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let keywords = [
            "card", "card number", "card no", "ending", "account",
            "xxxx", "****", "hsbc", "visa", "mastercard", "amex",
            "american express", "member", "會員", "会员", "卡號", "卡号"
        ]

        var selectedIndexes: Set<Int> = []
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let hasKeyword = keywords.contains { lower.contains($0) }
            let hasMaskedDigits = lower.contains("****") || lower.contains("xxxx")
            if hasKeyword || hasMaskedDigits {
                selectedIndexes.insert(index)
                if index > 0 { selectedIndexes.insert(index - 1) }
                if index + 1 < lines.count { selectedIndexes.insert(index + 1) }
            }
        }

        var selectedLines: [String] = []
        if selectedIndexes.isEmpty {
            selectedLines = Array(lines.prefix(30))
        } else {
            selectedLines = selectedIndexes.sorted().map { lines[$0] }
        }

        var prompt = selectedLines.joined(separator: "\n")
        let maxChars = 800
        if prompt.count > maxChars {
            prompt = String(prompt.prefix(maxChars))
        }
        return prompt
    }
}

// MARK: - Extension for withAnalysis

private extension ImportedTransaction {
    func withAnalysis(
        region: Region?,
        paymentMethod: PaymentMethod?,
        category: Category?,
        foreignAmount: Double?
    ) -> ImportedTransaction {
        let resolvedForeignAmount = foreignAmount ?? self.foreignAmount
        let resolvedRegion = region ?? self.region
        let resolvedForeignCurrency = resolvedRegion?.currencyCode
        return ImportedTransaction(
            id: id,
            transactionDate: transactionDate,
            postDate: postDate,
            merchant: merchant,
            billingAmount: billingAmount,
            foreignAmount: resolvedForeignAmount,
            foreignCurrency: resolvedForeignCurrency,
            region: region,
            paymentMethod: paymentMethod,
            category: category,
            rawText: rawText
        )
    }
}
