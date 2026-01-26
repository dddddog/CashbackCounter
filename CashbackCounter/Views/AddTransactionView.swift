import SwiftUI
import SwiftData

struct AddTransactionView: View {
    // 1. 环境与数据库
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Query var cards: [CreditCard]
    
    // 2. ViewModel 驱动
    @State private var viewModel: AddTransactionViewModel
    
    // 3. 回调
    var onSaved: (() -> Void)?
    
    // 4. 初始化：将数据传给 ViewModel
    init(repository: TransactionRepositoryProtocol, transaction: Transaction? = nil, image: UIImage? = nil, onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        self._viewModel = State(initialValue: AddTransactionViewModel(repository: repository, transaction: transaction, image: image))
    }

    var body: some View {
        NavigationView {
            Form {
                // --- 第一组：消费详情 ---
                Section(header: Text("消费详情")) {
                    TextField("商户名称 (例如：星巴克)", text: $viewModel.merchant)
                    
                    HStack {
                        Text(viewModel.location.currencySymbol)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        TextField("消费金额", text: $viewModel.amount)
                            .keyboardType(.decimalPad)
                    }
                    
                    Picker("消费类别", selection: $viewModel.selectedCategory) {
                        ForEach(Category.allCases, id: \.self) { c in
                            HStack {
                                Image(systemName: c.iconName).foregroundColor(c.color)
                                Text(c.displayName)
                            }
                            .tag(c)
                        }
                    }
                    
                    Picker("消费地区", selection: $viewModel.location) {
                        ForEach(Region.allCases, id: \.self) { r in
                            Text("\(r.icon) \(r.rawValue)").tag(r)
                        }
                    }
                }
                
                // --- 第二组：收据图片预览 ---
                Section(header: Text("收据凭证")) {
                    if let image = viewModel.receiptImage {
                        receiptPreview(image)
                    } else {
                        Button {
                            viewModel.showImagePicker = true
                        } label: {
                            Label("上传收据图片", systemImage: "photo.on.rectangle")
                        }
                    }
                }
            
                // --- 第三组：支付方式 ---
                Section(header: Text("支付方式")) {
                    if cards.isEmpty {
                        Text("请先添加信用卡").foregroundColor(.secondary)
                    } else {
                        Picker("选择信用卡", selection: $viewModel.selectedCardIndex) {
                            ForEach(0..<cards.count, id: \.self) { index in
                                Text(cards[index].bankName + " " + cards[index].type).tag(index)
                            }
                        }
                    }
                    
                    // 动态显示入账金额（当消费币种与卡片币种不一致时）
                    if cards.indices.contains(viewModel.selectedCardIndex) {
                        let card = cards[viewModel.selectedCardIndex]
                        if viewModel.location.currencySymbol != card.issueRegion.currencySymbol {
                            billingAmountField(symbol: card.issueRegion.currencySymbol)
                        }
                    }
                    
                    DatePicker("消费日期", selection: $viewModel.date, in: ...Date(), displayedComponents: .date)
                }
                
                // --- 第四组：返现预览 ---
                cashbackPreviewSection()
            }
            .navigationTitle(viewModel.transactionToEdit == nil ? "记一笔" : "编辑账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if viewModel.save(context: context, cards: cards) {
                            onSaved?()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.merchant.isEmpty || viewModel.amount.isEmpty || cards.isEmpty)
                }
            }
            .onAppear {
                // 如果是带图新建模式，触发 AI 分析
                viewModel.setupInitialCard(cards: cards)
                if viewModel.receiptImage != nil && viewModel.amount.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        viewModel.analyzeReceipt(cards: cards)
                    }
                }
            }
            .onChange(of: viewModel.receiptImage) { oldValue, newImage in
                if newImage != nil {
                    viewModel.analyzeReceipt(cards: cards) //
                }
            }
            // 监听变化，自动触发逻辑
            .onChange(of: viewModel.amount) { viewModel.updateBillingAmount(cards: cards) }
            .onChange(of: viewModel.location) { viewModel.updateBillingAmount(cards: cards) }
            .onChange(of: viewModel.selectedCardIndex) { viewModel.updateBillingAmount(cards: cards) }
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $viewModel.showImagePicker) {
                ImagePicker(selectedImage: $viewModel.receiptImage, sourceType: .photoLibrary)
            }
        }
    }
}

// MARK: - UI 组件拆分 (Helper Methods)
extension AddTransactionView {
    
    /// 收据预览及操作组件
    @ViewBuilder
    private func receiptPreview(_ image: UIImage) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(10)
                    .opacity(viewModel.isAnalyzing ? 0.5 : 1.0)
                    .onTapGesture { viewModel.showFullImage = true }
                
                if viewModel.isAnalyzing {
                    ProgressView("AI 分析中...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }
            }
            .sheet(isPresented: $viewModel.showFullImage) {
                ReceiptFullScreenView(image: image)
                    .presentationDragIndicator(.visible)
            }
            
            HStack {
                Button(role: .destructive) {
                    viewModel.receiptImage = nil
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    viewModel.showImagePicker = true
                } label: {
                    Label("重新上传", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// 入账金额输入组件
    @ViewBuilder
    private func billingAmountField(symbol: String) -> some View {
        HStack {
            Text("入账金额 (\(symbol))")
                .font(.caption)
                .foregroundColor(.red)
            Spacer()
            TextField("实际扣款", text: $viewModel.billingAmountStr)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    /// 返现预览组件
    @ViewBuilder
    private func cashbackPreviewSection() -> some View {
        Section(header: Text("返现预览")) {
            HStack {
                Text("预计返现")
                Spacer()
                
                if cards.indices.contains(viewModel.selectedCardIndex) {
                    let card = cards[viewModel.selectedCardIndex]
                    let amountDouble = Double(viewModel.amount) ?? 0
                    let finalAmount = Double(viewModel.billingAmountStr) ?? amountDouble
                    
                    // 从 ViewModel 获取计算好的返现额
                    let cashback = viewModel.getPreviewCashback(cards: cards)
                    
                    // 计算理论值用于颜色判断
                    let theoretical = finalAmount * card.getRate(for: viewModel.selectedCategory, location: viewModel.location)
                    
                    HStack(spacing: 4) {
                        Text("\(card.issueRegion.currencySymbol)\(String(format: "%.2f", cashback))")
                            .foregroundColor(cashback < theoretical - 0.01 ? .orange : .green)
                            .fontWeight(.bold)
                        
                        if cashback < theoretical - 0.01 {
                            Image(systemName: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                } else {
                    Text("¥0.00").foregroundColor(.gray)
                }
            }
        }
    }
}
