import SwiftUI
import SwiftData

@Model
class Transaction: Identifiable {
    var merchant: String
    var category: Category
    var location: Region
    
    var amount: Double        // 原币金额
    var billingAmount: Double // 入账金额
    
    var date: Date
    var cashbackamount: Double
    var rate: Double
    
    var card: CreditCard?
    
    // 👇 1. 新增字段：记录消费方式 (Apple Pay, 线下等)
    var paymentMethod: PaymentMethod
    
    @Attribute(.externalStorage) var receiptData: Data?
    
    @Relationship(deleteRule: .cascade, inverse: \Income.transaction)
    var incomes: [Income]?
    
    // 👇 2. 更新构造函数
    init(merchant: String,
         category: Category,
         location: Region,
         amount: Double,
         date: Date,
         card: CreditCard?,
         receiptData: Data? = nil,
         billingAmount: Double? = nil,
         cashbackAmount: Double? = nil,
         // 新增参数：设置默认值 .offline，这样旧代码不需要改动即可编译
         paymentMethod: PaymentMethod = .offline
    ) {
        self.merchant = merchant
        self.category = category
        self.location = location
        self.amount = amount
        self.date = date
        self.card = card
        self.receiptData = receiptData
        self.billingAmount = billingAmount ?? amount
        
        // 赋值
        self.paymentMethod = paymentMethod
        
        let finalBilling = billingAmount ?? amount
        
        // 计算名义费率
        // 注意：如果你后续更新了 CreditCard.getRate 支持 paymentMethod，这里也要跟着改
        // 目前先保持原逻辑，避免报错
        let nominalRate = card?.getRate(for: category, location: location, payment: paymentMethod) ?? 0
        
        if let providedCashback = cashbackAmount {
            self.cashbackamount = providedCashback
            self.rate = (providedCashback / finalBilling * 100).rounded() / 100
        } else {
            self.cashbackamount = finalBilling * nominalRate
            self.rate = nominalRate
        }
    }
    
    var color: Color { category.color }
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
