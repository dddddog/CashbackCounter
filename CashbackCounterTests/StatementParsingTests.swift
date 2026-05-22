import XCTest
import SwiftData
@testable import CashbackCounter

private typealias Category = CashbackCounter.Category

final class StatementParsingTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([CreditCard.self, Transaction.self, Point.self, PointAdjustment.self, Income.self])
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeImportedTransaction(
        merchant: String = "Apple Store",
        billingAmount: Double = 100.0,
        transactionDate: Date = Date(),
        postDate: Date? = nil,
        foreignAmount: Double? = nil,
        foreignCurrency: String? = nil,
        region: Region? = nil,
        paymentMethod: PaymentMethod? = nil,
        category: Category? = nil,
        rawText: String? = nil
    ) -> ImportedTransaction {
        ImportedTransaction(
            transactionDate: transactionDate,
            postDate: postDate ?? transactionDate,
            merchant: merchant,
            billingAmount: billingAmount,
            foreignAmount: foreignAmount,
            foreignCurrency: foreignCurrency,
            region: region,
            paymentMethod: paymentMethod,
            category: category,
            rawText: rawText
        )
    }

    private func makeTransaction(
        merchant: String = "Apple Store",
        amount: Double = 100.0,
        billingAmount: Double? = nil,
        category: Category = .digital,
        location: Region = .hk,
        date: Date = Date()
    ) -> Transaction {
        let card = CreditCard(
            bankName: "TestBank", type: "TestCard", endNum: "1234",
            colorHexes: ["FF0000"], defaultRate: 0.01,
            specialRates: [:], issueRegion: .hk
        )
        context.insert(card)
        let tx = Transaction(
            merchant: merchant,
            category: category,
            location: location,
            amount: amount,
            date: date,
            card: card,
            billingAmount: billingAmount
        )
        context.insert(tx)
        return tx
    }

    // MARK: - 1. ReconciliationEngine 测试

    func testReconciliation_AllMatched() {
        let now = Date()
        let imported = [
            makeImportedTransaction(merchant: "Apple Store", billingAmount: 100, transactionDate: now),
            makeImportedTransaction(merchant: "Starbucks", billingAmount: 50, transactionDate: now)
        ]
        let existing = [
            makeTransaction(merchant: "Apple Store", amount: 100, date: now),
            makeTransaction(merchant: "Starbucks", amount: 50, date: now)
        ]

        let engine = ReconciliationEngine()
        let report = engine.compare(imported: imported, existing: existing)

        XCTAssertEqual(report.matched.count, 2)
        XCTAssertEqual(report.missingInApp.count, 0)
    }

    func testReconciliation_AllMissing() {
        let now = Date()
        let imported = [
            makeImportedTransaction(merchant: "Apple Store", billingAmount: 100, transactionDate: now),
            makeImportedTransaction(merchant: "Starbucks", billingAmount: 50, transactionDate: now)
        ]
        let existing: [Transaction] = []

        let engine = ReconciliationEngine()
        let report = engine.compare(imported: imported, existing: existing)

        XCTAssertEqual(report.matched.count, 0)
        XCTAssertEqual(report.missingInApp.count, 2)
    }

    func testReconciliation_PartialMatch() {
        let now = Date()
        let imported = [
            makeImportedTransaction(merchant: "Apple Store", billingAmount: 100, transactionDate: now),
            makeImportedTransaction(merchant: "Starbucks", billingAmount: 50, transactionDate: now),
            makeImportedTransaction(merchant: "McDonald's", billingAmount: 30, transactionDate: now)
        ]
        let existing = [
            makeTransaction(merchant: "Apple Store", amount: 100, date: now)
        ]

        let engine = ReconciliationEngine()
        let report = engine.compare(imported: imported, existing: existing)

        XCTAssertEqual(report.matched.count, 1)
        XCTAssertEqual(report.missingInApp.count, 2)
    }

    func testReconciliation_AmountMismatch() {
        let now = Date()
        let imported = [
            makeImportedTransaction(merchant: "Apple Store", billingAmount: 100, transactionDate: now)
        ]
        // 金额差异 > 0.0001
        let existing = [
            makeTransaction(merchant: "Apple Store", amount: 100.01, date: now)
        ]

        let engine = ReconciliationEngine()
        let report = engine.compare(imported: imported, existing: existing)

        XCTAssertEqual(report.matched.count, 0, "金额差异 > 0.0001 应不匹配")
        XCTAssertEqual(report.missingInApp.count, 1)
    }

    func testReconciliation_DateOutOfRange() {
        let now = Date()
        let fourDaysLater = Calendar.current.date(byAdding: .day, value: 4, to: now)!

        let imported = [
            makeImportedTransaction(merchant: "Apple Store", billingAmount: 100, transactionDate: now)
        ]
        let existing = [
            makeTransaction(merchant: "Apple Store", amount: 100, date: fourDaysLater)
        ]

        let engine = ReconciliationEngine()
        let report = engine.compare(imported: imported, existing: existing)

        XCTAssertEqual(report.matched.count, 0, "日期差 >3 天应不匹配")
    }

    func testReconciliation_DateWithinRange() {
        let now = Date()
        let twoDaysLater = Calendar.current.date(byAdding: .day, value: 2, to: now)!

        let imported = [
            makeImportedTransaction(merchant: "Apple Store", billingAmount: 100, transactionDate: now)
        ]
        let existing = [
            makeTransaction(merchant: "Apple Store", amount: 100, date: twoDaysLater)
        ]

        let engine = ReconciliationEngine()
        let report = engine.compare(imported: imported, existing: existing)

        XCTAssertEqual(report.matched.count, 1, "日期差 <=3 天应匹配")
    }

    func testReconciliation_MerchantSubstring() {
        let now = Date()
        let imported = [
            makeImportedTransaction(merchant: "Apple Store HK Central", billingAmount: 100, transactionDate: now)
        ]
        let existing = [
            makeTransaction(merchant: "Apple Store", amount: 100, date: now)
        ]

        let engine = ReconciliationEngine()
        let report = engine.compare(imported: imported, existing: existing)

        XCTAssertEqual(report.matched.count, 1, "商户名子串包含应匹配")
    }

    func testReconciliation_EmptyMerchant() {
        let now = Date()
        let imported = [
            makeImportedTransaction(merchant: "", billingAmount: 100, transactionDate: now)
        ]
        let existing = [
            makeTransaction(merchant: "", amount: 100, date: now)
        ]

        let engine = ReconciliationEngine()
        let report = engine.compare(imported: imported, existing: existing)

        XCTAssertEqual(report.matched.count, 0, "空商户名应不匹配")
    }

    // MARK: - 2. ImportedTransaction 测试

    func testImportedTransaction_Identity() {
        let tx1 = makeImportedTransaction(merchant: "A", billingAmount: 10)
        let tx2 = makeImportedTransaction(merchant: "A", billingAmount: 10)

        // 每个都有唯一 id
        XCTAssertNotEqual(tx1.id, tx2.id)
    }

    func testImportedTransaction_Hashable() {
        let tx = makeImportedTransaction()
        var set = Set<ImportedTransaction>()
        set.insert(tx)
        set.insert(tx) // 插入同一个

        XCTAssertEqual(set.count, 1, "相同对象 hash 应一致")
    }

    func testImportedTransaction_ForeignFields() {
        let tx = makeImportedTransaction(
            merchant: "Amazon US",
            billingAmount: 780,
            foreignAmount: 100.0,
            foreignCurrency: "USD",
            region: .us
        )

        XCTAssertEqual(tx.foreignAmount, 100.0)
        XCTAssertEqual(tx.foreignCurrency, "USD")
        XCTAssertEqual(tx.region, .us)
    }

    // MARK: - 3. StatementMetadata 测试

    func testStatementMetadata_Init() {
        let transactions = [
            makeImportedTransaction(merchant: "A", billingAmount: 100),
            makeImportedTransaction(merchant: "B", billingAmount: 200)
        ]
        let metadata = StatementMetadata(
            totalBalance: 300.0,
            transactions: transactions,
            statementText: "Full statement text here",
            cardLast4: "5678",
            cardName: "HSBC Visa"
        )

        XCTAssertEqual(metadata.totalBalance, 300.0)
        XCTAssertEqual(metadata.transactions.count, 2)
        XCTAssertEqual(metadata.statementText, "Full statement text here")
        XCTAssertEqual(metadata.cardLast4, "5678")
        XCTAssertEqual(metadata.cardName, "HSBC Visa")
    }

    func testStatementMetadata_NilOptionals() {
        let metadata = StatementMetadata(totalBalance: nil, transactions: [])

        XCTAssertNil(metadata.totalBalance)
        XCTAssertNil(metadata.statementText)
        XCTAssertNil(metadata.cardLast4)
        XCTAssertNil(metadata.cardName)
        XCTAssertTrue(metadata.transactions.isEmpty)
    }
}
