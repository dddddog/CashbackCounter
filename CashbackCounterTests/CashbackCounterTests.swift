import XCTest
import SwiftData
@testable import CashbackCounter

private typealias Category = CashbackCounter.Category

final class CashbackCounterTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    // MARK: - Setup / Teardown

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

    // MARK: - Helper: 创建测试用信用卡

    private func makeCard(
        defaultRate: Double = 0.01,
        specialRates: [Category: Double] = [:],
        paymentMethodRates: [PaymentMethod: Double] = [:],
        issueRegion: Region = .hk,
        foreignCurrencyRate: Double? = nil,
        localBaseCap: Double = 0,
        foreignBaseCap: Double = 0,
        categoryCaps: [Category: Double] = [:],
        paymentCaps: [PaymentMethod: Double] = [:],
        capPeriod: CapPeriod = .yearly,
        rewardType: RewardType = .cashback,
        pointProgram: Point? = nil
    ) -> CreditCard {
        let card = CreditCard(
            bankName: "TestBank",
            type: "TestCard",
            endNum: "1234",
            colorHexes: ["FF0000"],
            defaultRate: defaultRate,
            specialRates: specialRates,
            issueRegion: issueRegion,
            foreignCurrencyRate: foreignCurrencyRate,
            localBaseCap: localBaseCap,
            foreignBaseCap: foreignBaseCap,
            categoryCaps: categoryCaps,
            capPeriod: capPeriod,
            paymentMethodRates: paymentMethodRates,
            paymentCaps: paymentCaps,
            rewardType: rewardType,
            pointProgram: pointProgram
        )
        context.insert(card)
        return card
    }

    private func makeTransaction(card: CreditCard, amount: Double, category: Category, paymentMethod: PaymentMethod = .offline, location: Region = .hk, date: Date = Date()) -> Transaction {
        let tx = Transaction(
            merchant: "Test Merchant",
            category: category,
            location: location,
            amount: amount,
            date: date,
            card: card,
            paymentMethod: paymentMethod
        )
        context.insert(tx)
        return tx
    }

    // MARK: - 1. 费率获取测试

    func testGetRate_Basic() {
        let card = makeCard(defaultRate: 0.01)
        XCTAssertEqual(card.getRate(for: .dining, location: .hk, payment: .offline), 0.01)
    }

    func testGetRate_CategoryBonus() {
        let card = makeCard(defaultRate: 0.01, specialRates: [.dining: 0.05])
        XCTAssertEqual(card.getRate(for: .dining, location: .hk, payment: .offline), 0.06, accuracy: 0.0001)
        XCTAssertEqual(card.getRate(for: .grocery, location: .hk, payment: .offline), 0.01, accuracy: 0.0001)
    }

    func testGetRate_PaymentBonus() {
        let card = makeCard(defaultRate: 0.01, paymentMethodRates: [.applePay: 0.02])
        XCTAssertEqual(card.getRate(for: .other, location: .hk, payment: .applePay), 0.03)
        XCTAssertEqual(card.getRate(for: .other, location: .hk, payment: .offline), 0.01)
    }

    func testGetRate_Foreign() {
        let card = makeCard(defaultRate: 0.01, foreignCurrencyRate: 0.02)
        XCTAssertEqual(card.getRate(for: .other, location: .us, payment: .offline), 0.02)
    }

    func testGetRate_Combined() {
        let card = makeCard(defaultRate: 0.01, specialRates: [.dining: 0.04], paymentMethodRates: [.applePay: 0.02], foreignCurrencyRate: 0.015)
        XCTAssertEqual(card.getRate(for: .dining, location: .us, payment: .applePay), 0.075) // 0.015 (foreign) + 0.04 (dining) + 0.02 (apple pay)
    }

    // MARK: - 2. 无封顶返现测试

    func testCalculateCashback_NoCaps() {
        let card = makeCard(defaultRate: 0.01, specialRates: [.dining: 0.05], paymentMethodRates: [.online: 0.02])
        
        // 100 * (0.01 + 0.05 + 0.02) = 100 * 0.08 = 8.0
        let cashback = card.calculateCappedCashback(amount: 100, category: .dining, location: .hk, date: Date(), paymentMethod: .online, transactionToExclude: nil)
        
        XCTAssertEqual(cashback, 8.0, accuracy: 0.0001)
    }

    // MARK: - 3. 三层封顶逻辑测试

    func testBaseCapTriggered() {
        // 基础封顶 10元
        let card = makeCard(defaultRate: 0.01, localBaseCap: 10)
        
        // 消费 2000，理论基础 20，但被封顶在 10
        let cashback = card.calculateCappedCashback(amount: 2000, category: .other, location: .hk, date: Date(), paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(cashback, 10.0, accuracy: 0.0001)
    }

    func testCategoryCapTriggered() {
        // 类别封顶 20元
        let card = makeCard(defaultRate: 0.01, specialRates: [.dining: 0.05], categoryCaps: [.dining: 20])
        
        // 消费 1000：基础 10 + 类别(1000*0.05=50 -> 封顶 20) = 30
        let cashback = card.calculateCappedCashback(amount: 1000, category: .dining, location: .hk, date: Date(), paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(cashback, 30.0, accuracy: 0.0001)
    }

    func testPaymentCapTriggered() {
        // 支付方式封顶 15元
        let card = makeCard(defaultRate: 0.01, paymentMethodRates: [.online: 0.03], paymentCaps: [.online: 15])
        
        // 消费 1000：基础 10 + 支付(1000*0.03=30 -> 封顶 15) = 25
        let cashback = card.calculateCappedCashback(amount: 1000, category: .other, location: .hk, date: Date(), paymentMethod: .online, transactionToExclude: nil)
        XCTAssertEqual(cashback, 25.0, accuracy: 0.0001)
    }

    func testAllCapsTriggered() {
        let card = makeCard(
            defaultRate: 0.01, specialRates: [.dining: 0.05], paymentMethodRates: [.online: 0.04],
            localBaseCap: 10, categoryCaps: [.dining: 20], paymentCaps: [.online: 15]
        )
        
        // 消费 2000：
        // 基础理论 20 -> 封顶 10
        // 类别理论 100 -> 封顶 20
        // 支付理论 80 -> 封顶 15
        // 总计：10 + 20 + 15 = 45
        let cashback = card.calculateCappedCashback(amount: 2000, category: .dining, location: .hk, date: Date(), paymentMethod: .online, transactionToExclude: nil)
        XCTAssertEqual(cashback, 45.0, accuracy: 0.0001)
    }

    // MARK: - 边界条件与异常输入测试
    
    func testCalculateCashback_ZeroAmount() async {
        let card = makeCard(defaultRate: 0.01)
        let cashback = card.calculateCappedCashback(amount: 0, category: .other, location: .hk, date: Date(), paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(cashback, 0.0)
    }

    func testCalculateCashback_FractionalAmount() async {
        let card = makeCard(defaultRate: 0.015)
        let cashback = card.calculateCappedCashback(amount: 10.55, category: .other, location: .hk, date: Date(), paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(cashback, 0.15825, accuracy: 0.0001)
    }

    func testCalculateCashback_NegativeAmount_Refund() async {
        // 退款应该扣除相应的返现
        let card = makeCard(defaultRate: 0.01, specialRates: [.dining: 0.05])
        let cashback = card.calculateCappedCashback(amount: -100, category: .dining, location: .hk, date: Date(), paymentMethod: .offline, transactionToExclude: nil)
        // 基础退 -1.0，类别退 -5.0 = -6.0
        XCTAssertEqual(cashback, -6.0, accuracy: 0.0001)
    }

    func testCalculateCashback_ExcludeTransaction() async {
        let card = makeCard(defaultRate: 0.01, localBaseCap: 10)
        let now = Date()
        
        // Transaction to exclude (which would normally consume the entire cap)
        let txToExclude = makeTransaction(card: card, amount: 1000, category: .other, date: now)
        
        // Calculate with exclusion
        let cashback = card.calculateCappedCashback(amount: 1000, category: .other, location: .hk, date: now, paymentMethod: .offline, transactionToExclude: txToExclude)
        XCTAssertEqual(cashback, 10.0, accuracy: 0.0001) // cap should not be consumed by txToExclude
    }

    func testCalculateCashback_ForeignBaseCap() async {
        let card = makeCard(defaultRate: 0.01, issueRegion: .hk, foreignCurrencyRate: 0.02, localBaseCap: 5, foreignBaseCap: 15)
        
        // 本地消费受限于 localBaseCap = 5
        let localCashback = card.calculateCappedCashback(amount: 1000, category: .other, location: .hk, date: Date(), paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(localCashback, 5.0, accuracy: 0.0001) // 1000 * 0.01 = 10 -> min(10, 5) = 5
        
        // 外币消费受限于 foreignBaseCap = 15
        let foreignCashback = card.calculateCappedCashback(amount: 1000, category: .other, location: .us, date: Date(), paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(foreignCashback, 15.0, accuracy: 0.0001) // 1000 * 0.02 = 20 -> min(20, 15) = 15
    }

    // MARK: - 4. 历史额度消耗与周期

    func testCapPartiallyUsedByHistory() {
        let card = makeCard(defaultRate: 0.01, localBaseCap: 10, capPeriod: .monthly)
        let now = Date()
        
        // 历史消费 500 (基础 5)，剩余额度 5
        _ = makeTransaction(card: card, amount: 500, category: .other, date: now)
        
        // 新消费 1000 (理论 10)，只能拿到剩余的 5
        let cashback = card.calculateCappedCashback(amount: 1000, category: .other, location: .hk, date: now, paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(cashback, 5.0, accuracy: 0.0001)
    }

    func testMonthlyCapReset() {
        let card = makeCard(defaultRate: 0.01, localBaseCap: 10, capPeriod: .monthly)
        let calendar = Calendar.current
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date())!
        let now = Date()
        
        // 上个月把额度刷满了
        _ = makeTransaction(card: card, amount: 2000, category: .other, date: lastMonth)
        
        // 这个月重新计算，全额拿到 10
        let cashback = card.calculateCappedCashback(amount: 1000, category: .other, location: .hk, date: now, paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(cashback, 10.0, accuracy: 0.0001)
    }

    func testYearlyCapReset_CrossYear() async {
        let card = makeCard(defaultRate: 0.01, specialRates: [.dining: 0.05], categoryCaps: [.dining: 20], capPeriod: .yearly)
        
        // 构造日期：去年 12 月 31 日
        var comps = DateComponents(year: 2025, month: 12, day: 31)
        let endOfLastYear = Calendar.current.date(from: comps)!
        
        // 构造日期：今年 1 月 1 日
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        let startOfThisYear = Calendar.current.date(from: comps)!
        
        // 去年年底把餐饮额度刷满了
        _ = makeTransaction(card: card, amount: 2000, category: .dining, date: endOfLastYear)
        
        // 去年年底再刷，餐饮部分应该没有了
        let lastYearCashback = card.calculateCappedCashback(amount: 1000, category: .dining, location: .hk, date: endOfLastYear, paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(lastYearCashback, 10.0, accuracy: 0.0001) // 基础 10 + 餐饮加成 0 (已达上限 20)
        
        // 今年年初刷，额度应当重置
        let thisYearCashback = card.calculateCappedCashback(amount: 1000, category: .dining, location: .hk, date: startOfThisYear, paymentMethod: .offline, transactionToExclude: nil)
        XCTAssertEqual(thisYearCashback, 30.0, accuracy: 0.0001) // 基础 10 + 餐饮加成(1000*0.05 = 50 -> 封顶 20) = 30
    }

    // MARK: - 5. 积分计算

    func testPointsCalculation() {
        let point = Point(bankName: "Bank", pointName: "PT", pointValue: 0.01, valueCurrencyCode: .hk)
        context.insert(point)
        
        // 积分卡，基础 1x，餐饮 5x (其实是加成 4x，这样总共 5x)
        let card = makeCard(defaultRate: 1.0, specialRates: [.dining: 4.0], rewardType: .points, pointProgram: point)
        
        // 消费 125，总计 125 * 5 = 625 积分
        let result = card.calculateCappedPoints(amount: 125, category: .dining, location: .hk, date: Date(), paymentMethod: .offline, pointValueInCardCurrency: 0.01, transactionToExclude: nil)
        
        XCTAssertEqual(result.points, 625)
    }

    func testPointsRounding() {
        let point = Point(bankName: "Bank", pointName: "PT", pointValue: 0.01, valueCurrencyCode: .hk)
        context.insert(point)
        let card = makeCard(defaultRate: 1.0, rewardType: .points, pointProgram: point)
        
        // 消费 125.6，积分应向下取整 floor(125.6) = 125
        let result = card.calculateCappedPoints(amount: 125.6, category: .other, location: .hk, date: Date(), paymentMethod: .offline, pointValueInCardCurrency: 0.01, transactionToExclude: nil)
        
        XCTAssertEqual(result.points, 125)
    }

}