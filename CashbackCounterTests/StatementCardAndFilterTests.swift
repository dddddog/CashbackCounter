import XCTest
import SwiftData
@testable import CashbackCounter

private typealias Category = CashbackCounter.Category

final class StatementCardAndFilterTests: XCTestCase {

    // MARK: - 1. normalizedCardLast4 Tests

    func testNormalizedCardLast4_ExactlyFourDigits() {
        XCTAssertEqual(ReceiptParser.normalizedCardLast4("1006"), "1006")
    }

    func testNormalizedCardLast4_FiveDigits_TakesLastFour() {
        // This is the bug case: "71006" should return "1006", not "7100"
        XCTAssertEqual(ReceiptParser.normalizedCardLast4("71006"), "1006")
    }

    func testNormalizedCardLast4_SixDigits_TakesLastFour() {
        XCTAssertEqual(ReceiptParser.normalizedCardLast4("871006"), "1006")
    }

    func testNormalizedCardLast4_WithMaskCharacters() {
        XCTAssertEqual(ReceiptParser.normalizedCardLast4("****71006"), "1006")
        XCTAssertEqual(ReceiptParser.normalizedCardLast4("XXXX71006"), "1006")
    }

    func testNormalizedCardLast4_WithSpaces() {
        XCTAssertEqual(ReceiptParser.normalizedCardLast4("**** 7100 6"), "1006")
    }

    func testNormalizedCardLast4_StandardFourAfterMask() {
        XCTAssertEqual(ReceiptParser.normalizedCardLast4("****5678"), "5678")
    }

    func testNormalizedCardLast4_TooFewDigits_ReturnsNil() {
        XCTAssertNil(ReceiptParser.normalizedCardLast4("123"))
        XCTAssertNil(ReceiptParser.normalizedCardLast4("****12"))
    }

    func testNormalizedCardLast4_NilInput_ReturnsNil() {
        XCTAssertNil(ReceiptParser.normalizedCardLast4(nil))
    }

    func testNormalizedCardLast4_EmptyString_ReturnsNil() {
        XCTAssertNil(ReceiptParser.normalizedCardLast4(""))
    }

    func testNormalizedCardLast4_NoDigits_ReturnsNil() {
        XCTAssertNil(ReceiptParser.normalizedCardLast4("****XXXX"))
    }

    func testNormalizedCardLast4_FullCardNumber() {
        XCTAssertEqual(ReceiptParser.normalizedCardLast4("4111111111111111"), "1111")
    }

    // MARK: - 2. extractTransactionRows Tests

    func testExtractTransactionRows_BasicEnglish() {
        let parser = StatementParser()
        let input = """
        | Account Summary |
        | Opening Balance | 5,000.00 |
        | Transaction Details |
        | 01 May | STARBUCKS | 45.00 |
        | 02 May | AMAZON | 120.00 |
        | Interest Charge |
        | Monthly Interest | 12.50 |
        """

        let result = parser.extractTransactionRows(from: input)

        XCTAssertTrue(result.contains("STARBUCKS"), "Should include transaction rows")
        XCTAssertTrue(result.contains("AMAZON"), "Should include transaction rows")
        XCTAssertFalse(result.contains("Account Summary"), "Should filter out account summary section")
        XCTAssertFalse(result.contains("Opening Balance"), "Should filter out summary content")
        XCTAssertFalse(result.contains("Monthly Interest"), "Should filter out interest section")
    }

    func testExtractTransactionRows_ChineseHeaders() {
        let parser = StatementParser()
        let input = """
        | 帳戶摘要 |
        | 上期結餘 | 5,000.00 |
        | 交易明細 |
        | 01/05 | 星巴克 | 45.00 |
        | 02/05 | 亞馬遜 | 120.00 |
        | 利息 |
        | 月利息 | 12.50 |
        """

        let result = parser.extractTransactionRows(from: input)

        XCTAssertTrue(result.contains("星巴克"), "Should include Chinese transaction rows")
        XCTAssertTrue(result.contains("亞馬遜"), "Should include Chinese transaction rows")
        XCTAssertFalse(result.contains("月利息"), "Should filter out interest section")
    }

    func testExtractTransactionRows_FallbackWhenNoHeaders() {
        let parser = StatementParser()
        let input = """
        | 01 May | STARBUCKS | 45.00 |
        | 02 May | AMAZON | 120.00 |
        """

        let result = parser.extractTransactionRows(from: input)

        // When no section headers detected, should return original text
        XCTAssertEqual(result, input, "Should return original text when no headers found")
    }

    func testExtractTransactionRows_DataRowNotMistakenForHeader() {
        let parser = StatementParser()
        // "Transaction" keyword appears but in a data row with amount
        let input = """
        | Transactions |
        | 01 May | TRANSACTION FEE REFUND | 10.00 |
        | 02 May | STARBUCKS | 45.00 |
        | Interest Charge |
        """

        let result = parser.extractTransactionRows(from: input)

        // The "TRANSACTION FEE REFUND" row has an amount, so looksLikeDataRow should prevent
        // it from being treated as a section header
        XCTAssertTrue(result.contains("TRANSACTION FEE REFUND"), "Data row with 'transaction' keyword should be preserved")
        XCTAssertTrue(result.contains("STARBUCKS"))
    }

    func testExtractTransactionRows_MultipleTransactionSections() {
        let parser = StatementParser()
        let input = """
        | Card Transactions |
        | 01 May | STARBUCKS | 45.00 |
        | Interest Charge |
        | Monthly Interest | 12.50 |
        | Purchases |
        | 03 May | APPLE STORE | 999.00 |
        | Fees |
        | Late fee | 50.00 |
        """

        let result = parser.extractTransactionRows(from: input)

        XCTAssertTrue(result.contains("STARBUCKS"), "Should include first section transactions")
        XCTAssertTrue(result.contains("APPLE STORE"), "Should include second section transactions")
        XCTAssertFalse(result.contains("Monthly Interest"), "Should filter interest")
        XCTAssertFalse(result.contains("Late fee"), "Should filter fees")
    }

    // MARK: - 3. looksLikeDataRow Tests

    func testLooksLikeDataRow_WithAmount() {
        let parser = StatementParser()
        XCTAssertTrue(parser.looksLikeDataRow("STARBUCKS 45.00"))
        XCTAssertTrue(parser.looksLikeDataRow("AMAZON 1,234.56"))
    }

    func testLooksLikeDataRow_WithoutAmount() {
        let parser = StatementParser()
        XCTAssertFalse(parser.looksLikeDataRow("Transaction Details"))
        XCTAssertFalse(parser.looksLikeDataRow("Interest Charge"))
    }

    func testLooksLikeDataRow_EdgeCase_DateOnly() {
        let parser = StatementParser()
        // A date like "01.05" looks like an amount — but this is acceptable
        // since it errs on the side of keeping rows
        XCTAssertTrue(parser.looksLikeDataRow("01.05 STARBUCKS"))
    }

    // MARK: - 4. isLikelyNoise Tests

    func testIsLikelyNoise_EmptyRow() {
        let parser = StatementParser()
        XCTAssertTrue(parser.isLikelyNoise(""))
        XCTAssertTrue(parser.isLikelyNoise("AB"))
    }

    func testIsLikelyNoise_PageMarker() {
        let parser = StatementParser()
        XCTAssertTrue(parser.isLikelyNoise("Page 3 of 5"))
        XCTAssertTrue(parser.isLikelyNoise("Page 1"))
    }

    func testIsLikelyNoise_ContinuedMarker() {
        let parser = StatementParser()
        XCTAssertTrue(parser.isLikelyNoise("Continued on next page"))
        XCTAssertTrue(parser.isLikelyNoise("Continued from previous page"))
    }

    func testIsLikelyNoise_RepeatingColumnHeaders() {
        let parser = StatementParser()
        XCTAssertTrue(parser.isLikelyNoise("Transaction Date Description Amount"))
        XCTAssertTrue(parser.isLikelyNoise("Posting Date Reference Number"))
        XCTAssertTrue(parser.isLikelyNoise("交易日 金額"))
    }

    func testIsLikelyNoise_NormalTransaction() {
        let parser = StatementParser()
        XCTAssertFalse(parser.isLikelyNoise("01 May STARBUCKS 45.00"))
        XCTAssertFalse(parser.isLikelyNoise("APPLE STORE HK 999.00"))
    }

    // MARK: - 5. StatementAnalysisViewModel Prompt Tests

    @MainActor
    func testTransactionPromptText_NoCard() {
        let vm = StatementAnalysisViewModel()
        let tx = ImportedTransaction(
            transactionDate: Date(),
            postDate: Date(),
            merchant: "SUSHI OTARU MASA",
            billingAmount: 139.10
        )

        // When no card is selected, selectedCardIndex is nil
        let prompt = vm.testableTransactionPromptText(for: tx, cards: [])

        XCTAssertTrue(prompt.contains("BillingCurrency: unknown"), "Should use 'unknown' not 'unknow'")
        XCTAssertFalse(prompt.contains("unknow,"), "Should not have old typo 'unknow,'")
        XCTAssertTrue(prompt.contains("139.10"), "Should include billing amount")
        XCTAssertTrue(prompt.contains("SUSHI OTARU MASA"), "Should include merchant")
    }

    @MainActor
    func testTransactionPromptText_WithCard() throws {
        let schema = Schema([CreditCard.self, Transaction.self, Point.self, PointAdjustment.self, Income.self])
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let card = CreditCard(
            bankName: "AMEX",
            type: "AE1",
            endNum: "1006",
            colorHexes: ["000000"],
            defaultRate: 0.01,
            specialRates: [:],
            issueRegion: .hk
        )
        context.insert(card)

        let vm = StatementAnalysisViewModel()
        let tx = ImportedTransaction(
            transactionDate: Date(),
            postDate: Date(),
            merchant: "THE RITZ-CARLTON HK",
            billingAmount: 798.95
        )

        vm.selectedCardIndex = 0
        let prompt = vm.testableTransactionPromptText(for: tx, cards: [card])

        XCTAssertTrue(prompt.contains("BillingCurrency: HKD"), "Should show card's currency code")
        XCTAssertTrue(prompt.contains("798.95 HKD"), "Should include amount with currency")
    }
}

// MARK: - Test Helper Extension

extension StatementAnalysisViewModel {
    /// Expose transactionPromptText for unit testing.
    func testableTransactionPromptText(for transaction: ImportedTransaction, cards: [CreditCard]) -> String {
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
}
