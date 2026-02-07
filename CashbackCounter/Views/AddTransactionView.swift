import SwiftUI
import SwiftData

struct AddTransactionView: View {
    // 1. 数据库与环境
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Query var cards: [CreditCard]
    
    // 2. 回调与编辑对象
    var onSaved: (() -> Void)? = nil
    var transactionToEdit: Transaction?
    private let prefillCardLast4: String?
    private let shouldSkipRateUpdate: Bool
    
    // --- 表单的状态变量 ---
    @State private var merchant: String = ""
    @State private var amount: String = ""
    @State private var selectedCategory: Category = .dining
    @State private var date: Date = Date()
    @State private var selectedCardIndex: Int = 0
    @State private var location: Region = .cn
    @State private var billingAmountStr: String = ""
    @State private var receiptImage: UIImage?
    
    // 👇 1. 确保有这个状态变量
    @State private var paymentMethod: PaymentMethod = .offline
    
    // AI 分析状态
    @State private var isAnalyzing: Bool = false
    @State private var showFullImage = false
    @State private var showImagePicker: Bool = false

    
    // --- 3. 自定义初始化 ---
    init(
        transaction: Transaction? = nil,
        image: UIImage? = nil,
        prefillMerchant: String? = nil,
        prefillAmount: Double? = nil,
        prefillBillingAmount: Double? = nil,
        prefillDate: Date? = nil,
        prefillCategory: Category? = nil,
        prefillLocation: Region? = nil,
        prefillPaymentMethod: PaymentMethod? = nil,
        prefillCardLast4: String? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.transactionToEdit = transaction
        self.onSaved = onSaved
        self.prefillCardLast4 = prefillCardLast4
        self.shouldSkipRateUpdate = transaction != nil || prefillBillingAmount != nil

        if let t = transaction {
            // 编辑模式
            _merchant = State(initialValue: t.merchant)
            _amount = State(initialValue: String(t.amount))
            _billingAmountStr = State(initialValue: String(t.billingAmount))
            _selectedCategory = State(initialValue: t.category)
            _date = State(initialValue: t.date)
            _location = State(initialValue: t.location)
            // 👇 初始化消费方式
            _paymentMethod = State(initialValue: t.paymentMethod)
            
            if let data = t.receiptData {
                _receiptImage = State(initialValue: UIImage(data: data))
            }
        } else {
            // 新建模式
            _receiptImage = State(initialValue: image)
            
            if let prefillMerchant {
                _merchant = State(initialValue: prefillMerchant)
            }
            
            let displayAmount = prefillAmount ?? prefillBillingAmount
            if let displayAmount {
                let formattedAmount = String(format: "%.2f", displayAmount)
                _amount = State(initialValue: formattedAmount)
            }

            if let prefillBillingAmount {
                _billingAmountStr = State(initialValue: String(format: "%.2f", prefillBillingAmount))
            } else if let displayAmount {
                _billingAmountStr = State(initialValue: String(format: "%.2f", displayAmount))
            }
            
            if let prefillDate {
                _date = State(initialValue: prefillDate)
            }

            if let prefillCategory {
                _selectedCategory = State(initialValue: prefillCategory)
            }

            if let prefillLocation {
                _location = State(initialValue: prefillLocation)
            }

            if let prefillPaymentMethod {
                _paymentMethod = State(initialValue: prefillPaymentMethod)
            }
        }
    }
    
    var currentCurrencySymbol: String {
        if cards.indices.contains(selectedCardIndex) {
            let card = cards[selectedCardIndex]
            return card.issueRegion.currencySymbol
        }
        return "¥"
    }
    
    var body: some View {
        NavigationView {
            Form {
                // --- 第一组：消费详情 ---
                Section(header: Text("消费详情")) {
                    TextField("商户名称 (例如：星巴克)", text: $merchant)
                    
                    HStack {
                        Text(location.currencySymbol)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        TextField("消费金额", text: $amount)
                            .keyboardType(.decimalPad)
                    }
                    
                    Picker("消费类别", selection: $selectedCategory) {
                        ForEach(Category.allCases, id: \.self) { c in
                            HStack {
                                Image(systemName: c.iconName).foregroundColor(c.color)
                                Text(c.displayName)
                            }
                            .tag(c)
                        }
                    }
                    
                    // 👇 新增：消费方式选择器
                    Picker("交易类型", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Label(method.displayName, systemImage: method.iconName)
                                .foregroundColor(method.color) // 使用我们在 Enum 里定义的颜色
                                .tag(method)
                        }
                    }
                    
                    Picker("消费地区", selection: $location) {
                        ForEach(Region.allCases, id: \.self) { r in
                            Text("\(r.icon) \(r.rawValue)").tag(r)
                        }
                    }
                }
                
                // --- 第二组：收据凭证 ---
                Section(header: Text("收据凭证")) {
                    if let image = receiptImage {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(10)
                                .opacity(isAnalyzing ? 0.5 : 1.0)
                                .onTapGesture {
                                    showFullImage = true
                                }
                            
                            if isAnalyzing {
                                ProgressView("AI 分析中...")
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(10)
                            }
                        }
                        .sheet(isPresented: $showFullImage){
                            ReceiptFullScreenView(image: image)
                                .presentationDragIndicator(.visible)
                        }
                        Button(role: .destructive) {
                            receiptImage = nil
                        } label: {
                            Label("删除图片", systemImage: "trash")
                        }
                        
                        Button {
                            showImagePicker = true
                        } label: {
                            Label("重新上传", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } else {
                        Button {
                            showImagePicker = true
                        } label: {
                            Label("上传收据图片", systemImage: "photo.on.rectangle")
                        }
                    }
                }
            
                
                // --- 第三组：支付账户与日期 ---
                Section(header: Text("支付账户")) {
                    if cards.isEmpty {
                        Text("请先添加信用卡").foregroundColor(.secondary)
                    } else {
                        Picker("选择信用卡", selection: $selectedCardIndex) {
                            ForEach(0..<cards.count, id: \.self) { index in
                                Text(cards[index].bankName + " " + cards[index].type).tag(index)
                            }
                        }
                    }
                    
                    if cards.indices.contains(selectedCardIndex) {
                        let card = cards[selectedCardIndex]
                        if location.currencySymbol != card.issueRegion.currencySymbol {
                            HStack {
                                Text("入账金额 (\(card.issueRegion.currencySymbol))")
                                    .font(.caption).foregroundColor(.red)
                                Spacer()
                                TextField("实际扣款", text: $billingAmountStr)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    
                    DatePicker("消费日期", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                
                // --- 第四组：实时预算返现 ---
                Section {
                    HStack {
                        Text("预计返现")
                        Spacer()
                        
                        // 使用刚才抽离的计算属性
                        if let preview = cashbackPreview {
                            HStack(spacing: 4) {
                                Text("\(currentCurrencySymbol)\(String(format: "%.2f", preview.amount))")
                                    .foregroundColor(preview.isCapped ? .orange : .green)
                                    .fontWeight(.bold)
                                
                                if preview.isCapped {
                                    Image(systemName: "exclamationmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        } else {
                            // 金额无效或未选卡时
                            Text("¥0.00").foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle(transactionToEdit == nil ? "记一笔" : "编辑账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveTransaction() }
                        .disabled(merchant.isEmpty || amount.isEmpty || cards.isEmpty)
                }
            }
            .onAppear {
                if let t = transactionToEdit, let card = t.card,
                   let index = cards.firstIndex(of: card) {
                    selectedCardIndex = index
                } else {
                    applyPrefillCardSelection()
                    if receiptImage != nil && amount.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            analyzeReceipt()
                        }
                    }
                }
            }
            .onChange(of: cards.count) { _, _ in
                applyPrefillCardSelection()
            }
            .onChange(of: receiptImage) { _, newImage in
                if newImage != nil { analyzeReceipt() }
            }
            .onChange(of: amount) { updateBillingAmount() }
            .onChange(of: location) { updateBillingAmount() }
            .onChange(of: selectedCardIndex) { updateBillingAmount() }
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $receiptImage, sourceType: .photoLibrary)
            }
        }
    }
    
    // --- 4. AI 分析逻辑 (保持不变，或在此处根据 metadata 自动推断 paymentMethod) ---
    private func applyPrefillCardSelection() {
        guard transactionToEdit == nil else { return }
        guard let prefillCardLast4 else { return }
        guard let index = cards.firstIndex(where: { $0.endNum == prefillCardLast4 }) else { return }
        selectedCardIndex = index
    }

    func analyzeReceipt() {
        // ... (保持你原有的逻辑不变) ...
        guard let image = receiptImage else { return }
        if !merchant.isEmpty || !amount.isEmpty { return }
        isAnalyzing = true
        
        Task {
            let metadata = await OCRService.analyzeImage(image)
            await MainActor.run {
                isAnalyzing = false
                if let data = metadata {
                    if let amt = data.totalAmount { self.amount = String(format: "%.2f", abs(amt)) }
                    if let merch = data.merchant { self.merchant = merch }
                    if let dateStr = data.dateString { self.date = dateStr.toDate() }
                    if let last4 = data.cardLast4, let index = cards.firstIndex(where: { $0.endNum == last4 }) {
                        self.selectedCardIndex = index
                    }
                    if let cat = data.category { self.selectedCategory = cat }
                    if let currency = data.currency {
                        if currency.contains("CNY") { self.location = .cn }
                        else if currency.contains("USD") { self.location = .us }
                        else if currency.contains("HKD") { self.location = .hk }
                        else if currency.contains("JPY") { self.location = .jp }
                        else { self.location = .other }
                    }
                }
            }
        }
    }
    // MARK: - 抽离的计算逻辑
    // 返回值：(返现金额, 是否被上限卡住)
    private var cashbackPreview: (amount: Double, isCapped: Bool)? {
        // 1. 基础校验
        guard let amountDouble = Double(amount),
              cards.indices.contains(selectedCardIndex) else {
            return nil
        }
        
        let card = cards[selectedCardIndex]
        // 优先使用 billingAmountStr (如果有值)，否则用 amount
        let finalAmount = Double(billingAmountStr) ?? amountDouble
        
        // 2. 计算实际返现 (调用你的 Core Function)
        let cashback = card.calculateCappedCashback(
            amount: finalAmount,
            category: selectedCategory,
            location: location,
            date: date,
            paymentMethod: paymentMethod,
            transactionToExclude: transactionToEdit
        )
        
        // 3. 计算理论返现 (用于判断颜色)
        // ⚠️ 注意：既然你修改了 getRate，这里请根据你的 getRate 签名来写
        // 情况 A：如果你把 paymentMethod 加进去了，就用：
        let theoreticalRate = card.getRate(for: selectedCategory, location: location, payment: paymentMethod)
        
        let theoretical = finalAmount * theoreticalRate
        
        // 判断是否被 Cap (实际 < 理论 - 误差)
        let isCapped = cashback < (theoretical - 0.01)
        
        return (cashback, isCapped)
    }
    // --- 核心保存逻辑 ---
    func saveTransaction() {
        guard let amountDouble = Double(amount) else { return }
        let billingDouble = Double(billingAmountStr) ?? amountDouble
        
        if cards.indices.contains(selectedCardIndex) {
            let card = cards[selectedCardIndex]
            let imageData = receiptImage?.jpegData(compressionQuality: 0.5)
            
            // 1. 计算最终返现 (包含 PaymentMethod)
            let finalCashback = card.calculateCappedCashback(
                amount: billingDouble,
                category: selectedCategory,
                location: location,
                date: date,
                paymentMethod: paymentMethod, // 👈 传入
                transactionToExclude: transactionToEdit
            )
            
            // 2. 计算名义费率
            // 如果你的 CreditCard.getRate 还没更新支持 payment，这里我们手动加一下
            // 确保 CreditCard 类里有 paymentMethodRates 字典
            let baseRate = card.getRate(for: selectedCategory, location: location,payment: paymentMethod)
            let nominalRate = baseRate
            
            if let t = transactionToEdit {
                // --- 编辑模式 ---
                t.merchant = merchant
                t.amount = amountDouble
                t.location = location
                t.date = date
                
                // 检查关键属性变更
                if t.card != card ||
                    t.billingAmount != billingDouble ||
                    t.category != selectedCategory ||
                    t.paymentMethod != paymentMethod || // 👈 检查消费方式变化
                    t.date != date ||
                    t.cashbackamount != finalCashback {
                    
                    t.card = card
                    t.billingAmount = billingDouble
                    t.category = selectedCategory
                    t.paymentMethod = paymentMethod // 👈 更新数据库字段
                    
                    t.rate = nominalRate
                    t.cashbackamount = finalCashback
                }
                
                if let img = imageData { t.receiptData = img }else {
                    t.receiptData = nil
                }
                
            } else {
                // --- 新建模式 ---
                let newTransaction = Transaction(
                    merchant: merchant,
                    category: selectedCategory,
                    location: location,
                    amount: amountDouble,
                    date: date,
                    card: card,
                    receiptData: imageData,
                    billingAmount: billingDouble,
                    cashbackAmount: finalCashback,
                    paymentMethod: paymentMethod // 👈 写入数据库
                )
                context.insert(newTransaction)
            }
            
            dismiss()
            onSaved?()
        }
    }
    
    func updateBillingAmount() {
        // ... (保持你原有的逻辑不变) ...
        guard let amountDouble = Double(amount) else { return }
        guard cards.indices.contains(selectedCardIndex) else {
            billingAmountStr = amount
            return
        }
        let sourceCurrency = location.currencyCode
        let card = cards[selectedCardIndex]
        let targetCurrency = card.issueRegion.currencyCode
        
        if sourceCurrency == targetCurrency || sourceCurrency == "TWD" || sourceCurrency == "EUR" {
            billingAmountStr = amount
            return
        }
        guard transactionToEdit == nil else { return }
        if shouldSkipRateUpdate{
            return
        }

        Task {
            do {
                let rate = try await CurrencyService.fetchRate(from: sourceCurrency, to: targetCurrency)
                let billing = amountDouble * rate
                await MainActor.run {
                    self.billingAmountStr = String(format: "%.2f", billing)
                }
            } catch {
                print("汇率获取失败: \(error)")
            }
        }
    }
}
