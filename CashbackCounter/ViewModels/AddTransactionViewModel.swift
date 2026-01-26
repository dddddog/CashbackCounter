import SwiftUI
import SwiftData

@Observable
class AddTransactionViewModel {
    private let repository: TransactionRepositoryProtocol
    // --- 1. 状态变量 (用于 UI 绑定) ---
    var merchant: String = ""
    var amount: String = ""
    var selectedCategory: Category = .dining
    var date: Date = Date()
    var selectedCardIndex: Int = 0
    var location: Region = .cn
    var billingAmountStr: String = ""
    var receiptImage: UIImage?
    
    // --- 2. UI 控制状态 ---
    var isAnalyzing: Bool = false
    var showFullImage: Bool = false
    var showImagePicker: Bool = false
    
    // --- 3. 内部数据引用 ---
    // 持有编辑对象，用于保存时更新或计算返现时排除自身
    var transactionToEdit: Transaction?

    // --- 4. 初始化方法 (处理新建/带图新建/编辑模式) ---
    init(repository: TransactionRepositoryProtocol, transaction: Transaction? = nil, image: UIImage? = nil) {
        self.repository = repository
        self.transactionToEdit = transaction
        
        if let t = transaction {
            // 编辑模式：从数据库模型同步到 VM 状态
            self.merchant = t.merchant
            self.amount = String(t.amount)
            self.billingAmountStr = String(t.billingAmount)
            self.selectedCategory = t.category
            self.date = t.date
            self.location = t.location
            if let data = t.receiptData {
                self.receiptImage = UIImage(data: data)
            }
        } else {
            // 新建模式：初始化传入的图片（如有）
            self.receiptImage = image
        }
    }

    // --- 5. 业务逻辑：汇率自动换算 ---
    func updateBillingAmount(cards: [CreditCard]) {
        guard let amountDouble = Double(amount) else { return }
        
        guard cards.indices.contains(selectedCardIndex) else {
            billingAmountStr = amount
            return
        }

        let card = cards[selectedCardIndex]
        let sourceCurrency = location.currencyCode
        let targetCurrency = card.issueRegion.currencyCode
        
        // 如果币种相同或属于免换算币种，直接同步金额
        if sourceCurrency == targetCurrency || ["TWD", "EUR"].contains(sourceCurrency) {
            billingAmountStr = amount
            return
        }
        
        // 仅在新建模式下自动请求汇率，避免污染历史账单
        guard transactionToEdit == nil else { return }

        Task {
            do {
                // 调用 CurrencyService 获取实时汇率
                let rate = try await CurrencyService.fetchRate(from: sourceCurrency, to: targetCurrency)
                
                await MainActor.run {
                    self.billingAmountStr = String(format: "%.2f", amountDouble * rate)
                }
            } catch {
                print("汇率获取失败: \(error)")
            }
        }
    }

    // --- 6. 业务逻辑：AI 收据分析 (OCR) ---
    func analyzeReceipt(cards: [CreditCard]) {
        guard let image = receiptImage else { return }
        
        
        isAnalyzing = true
        
        Task {
            // 调用 OCRService 进行图像识别
            let metadata = await OCRService.analyzeImage(image)
            
            await MainActor.run {
                self.isAnalyzing = false
                
                if let data = metadata {
                    if let amt = data.totalAmount { self.amount = String(format: "%.2f", abs(amt)) }
                    if let merch = data.merchant { self.merchant = merch }
                    if let dateStr = data.dateString { self.date = dateStr.toDate() }
                    
                    // 自动匹配信用卡尾号
                    if let last4 = data.cardLast4 {
                        if let index = cards.firstIndex(where: { $0.endNum == last4 }) {
                            self.selectedCardIndex = index
                        }
                    }
                    
                    if let cat = data.category { self.selectedCategory = cat }
                    
                    // 自动识别消费地区
                    if let currency = data.currency {
                        updateLocationFromCurrency(currency)
                    }
                }
            }
        }
    }

    // --- 7. 业务逻辑：计算预览返现额 ---
    func getPreviewCashback(cards: [CreditCard]) -> Double {
        guard let amountDouble = Double(amount), cards.indices.contains(selectedCardIndex) else { return 0.0 }
        
        let card = cards[selectedCardIndex]
        let finalAmount = Double(billingAmountStr) ?? amountDouble
        
        // 调用 CreditCard 模型内的返现计算逻辑，并传入 transactionToEdit 以正确计算上限
        return card.calculateCappedCashback(
            amount: finalAmount,
            category: selectedCategory,
            location: location,
            date: date,
            transactionToExclude: transactionToEdit
        )
    }
    func setupInitialCard(cards: [CreditCard]) {
        // 如果是编辑模式，且账单有关联的卡片
        if let t = transactionToEdit, let card = t.card {
            // 在当前的 cards 数组中查找该卡片的索引
            if let index = cards.firstIndex(where: { $0.id == card.id }) {
                self.selectedCardIndex = index
            }
        }
    }

    // --- 8. 核心逻辑：保存交易 ---
    func save(context: ModelContext, cards: [CreditCard]) -> Bool {
        guard let amountDouble = Double(amount), cards.indices.contains(selectedCardIndex) else { return false }
        
        let card = cards[selectedCardIndex]
        let billingDouble = Double(billingAmountStr) ?? amountDouble
        let imageData = receiptImage?.jpegData(compressionQuality: 0.5)
        
        // 保存前最后计算一次实际返现额
        let finalCashback = getPreviewCashback(cards: cards)
        let nominalRate = card.getRate(for: selectedCategory, location: location)
        
        if let t = transactionToEdit {
            // --- 编辑模式：更新现有数据 ---
            t.merchant = merchant
            t.amount = amountDouble
            t.location = location
            t.date = date
            t.card = card
            t.billingAmount = billingDouble
            t.category = selectedCategory
            t.rate = nominalRate
            t.cashbackamount = finalCashback
            if let img = imageData { t.receiptData = img }
        } else {
            // --- 新建模式：创建新实例并插入数据库 ---
            let newTransaction = Transaction(
                merchant: merchant,
                category: selectedCategory,
                location: location,
                amount: amountDouble,
                date: date,
                card: card,
                receiptData: imageData,
                billingAmount: billingDouble,
                cashbackAmount: finalCashback
            )
            repository.insert(newTransaction) // ✅ 使用 repository
        }
        do {
            try repository.save() // ✅ 统一保存入口
            return true
        } catch {
            print("保存失败: \(error)")
            return false
        }
    }
    
    // 辅助：从货币字符串识别地区
    private func updateLocationFromCurrency(_ currency: String) {
        if currency.contains("CNY") { self.location = .cn }
        else if currency.contains("USD") { self.location = .us }
        else if currency.contains("HKD") { self.location = .hk }
        else if currency.contains("JPY") { self.location = .jp }
        else if currency.contains("NZD") { self.location = .nz }
        else if currency.contains("TWD") { self.location = .tw }
        else { self.location = .other }
    }
}
