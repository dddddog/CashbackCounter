import SwiftUI
import SwiftData
import UniformTypeIdentifiers // 确保引入以支持文件导入

struct BillHomeView: View {
    // 1. 数据库上下文
    @Environment(\.modelContext) var context
    
    // 按日期倒序、商户名正序排列
    @Query(
        sort: [
            SortDescriptor(\Transaction.date, order: .reverse),
            SortDescriptor(\Transaction.merchant, order: .forward)
        ]
    )
    var dbTransactions: [Transaction]
    
    // 2. 弹窗状态
    @State private var selectedTransaction: Transaction? = nil
    @State private var transactionToEdit: Transaction?
    @State private var incomeTargetTransaction: Transaction?
    @State private var incomeToEdit: Income?
    @State private var showDatePicker = false
    
    // 3. 筛选状态
    @State private var selectedDate = Date()
    @State private var showAll = false
    @State private var isWholeYear = true
    @State private var selectedCategory: Category? = nil
    @State private var showIncomeOnly = false
    
    // 👇 新增：搜索文本状态
    @State private var searchText = ""
    @State private var isSearchPresented = false

    // 趋势图与导入状态
    @Query var cards: [CreditCard]
    @State private var showTrendSheet = false
    @State private var showExpenseSheet = false
    @State private var showFileImporter = false
    @State private var showImportAlert = false
    @State private var importMessage = ""
    @State private var showStatementAnalysis = false

    // 4. 汇率表
    @State private var exchangeRates: [String: Double] = [:]
    @AppStorage("mainCurrencyCode") private var mainCurrencyCode: String = "CNY"
    
    // 5. 核心筛选逻辑 (不含支付方式)
    var filteredTransactions: [Transaction] {
        let query = trimmedSearchText
        if isSearchingActive {
            return dbTransactions.filter { matchesSearch($0, query: query) }
        }

        // 第一步：日期筛选
        var results = showAll ? dbTransactions : dbTransactions.filter { t in
            if isWholeYear {
                return Calendar.current.isDate(t.date, equalTo: selectedDate, toGranularity: .year)
            } else {
                return Calendar.current.isDate(t.date, equalTo: selectedDate, toGranularity: .month)
            }
        }

        // 第二步：按类别筛选
        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }

        // 第三步：按收入筛选
        if showIncomeOnly {
            results = results.filter { ($0.incomes?.isEmpty == false) }
        }

        return results
    }
    
    // 按钮显示的日期文字
    var dateButtonText: String {
        if isWholeYear {
            return selectedDate.formatted(.dateTime.year()) + " 全年"
        } else {
            return selectedDate.formatted(.dateTime.year().month())
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchingActive: Bool {
        !trimmedSearchText.isEmpty
    }

    private var isSearchFieldActive: Bool {
        isSearchPresented || isSearchingActive
    }

    private var expenseTitle: LocalizedStringKey {
        if isSearchingActive || showAll {
            return "总支出"
        }
        return isWholeYear ? "本年支出" : "本月支出"
    }

    private var cashbackTitle: LocalizedStringKey {
        if isSearchingActive || showAll {
            return "总返现"
        }
        return isWholeYear ? "本年返现" : "本月返现"
    }

    private func matchesSearch(_ transaction: Transaction, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        func contains(_ value: String) -> Bool {
            value.localizedCaseInsensitiveContains(needle)
        }

        var candidates: [String] = [
            transaction.merchant,
            transaction.category.displayName,
            transaction.location.currencyCode,
            transaction.paymentMethod.displayName,
            transaction.dateString,
            String(format: "%.2f", transaction.amount),
            String(format: "%.2f", transaction.billingAmount),
            String(format: "%.2f", transaction.cashbackamount),
            String(transaction.pointsEarned),
            String(format: "%.2f", transaction.rate)
        ]

        if let card = transaction.card {
            candidates.append(contentsOf: [
                card.bankName,
                card.type,
                card.endNum,
                card.issueRegion.rawValue,
                card.issueRegion.currencyCode
            ])
        }

        if let incomes = transaction.incomes, !incomes.isEmpty {
            for income in incomes {
                candidates.append(contentsOf: [
                    income.detail,
                    income.platform,
                    income.location.rawValue,
                    income.location.currencyCode,
                    income.dateString,
                    String(format: "%.2f", income.amount)
                ])
            }
        }

        return candidates.contains { contains($0) }
    }

    @ViewBuilder
    private var filterBar: some View {
        if !isSearchFieldActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // 左侧留白
                    Spacer().frame(width: 16)
                    
                    // A. 类别筛选
                    Menu {
                        Button(action: { selectedCategory = nil }) {
                            Label("全部种类", systemImage: "checkmark.circle")
                        }
                        ForEach(Category.allCases, id: \.self) { category in
                            Button(action: { selectedCategory = category }) {
                                Label(category.displayName, systemImage: category.iconName)
                            }
                        }
                    } label: {
                        FilterChip(
                            title: selectedCategory?.displayName ?? "全部种类",
                            icon: selectedCategory?.iconName ?? "line.3.horizontal.decrease.circle",
                            isSelected: selectedCategory != nil
                        )
                    }

                    // B. 收入筛选
                    Button(action: { showIncomeOnly.toggle() }) {
                        FilterChip(
                            title: "收入单",
                            icon: "tray.and.arrow.down.fill",
                            isSelected: showIncomeOnly
                        )
                    }

                    // C. 日期筛选
                    Button(action: { showDatePicker = true }) {
                        FilterChip(
                            title: dateButtonText,
                            icon: "calendar",
                            isSelected: !showAll
                        )
                    }
                    
                    // 右侧留白
                    Spacer().frame(width: 16)
                }
            }
        }
    }

    @ViewBuilder
    private var statsBar: some View {
        HStack(spacing: 15) {
            // 支出统计 -> 红色趋势图
            Button(action: { showExpenseSheet = true }) {
                StatBox(
                    title: expenseTitle,
                    amount: exchangeRates.isEmpty ? "..." : String(format: "%.2f", totalExpense),
                    icon: "arrow.down.circle.fill", color: .red
                )
                .overlay(
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(.gray.opacity(0.5)).padding(.trailing, 10),
                    alignment: .trailing
                )
            }
            .buttonStyle(.plain)
            
            // 返现统计 -> 绿色趋势图
            Button(action: { showTrendSheet = true }) {
                StatBox(
                    title: cashbackTitle,
                    amount: exchangeRates.isEmpty ? "..." : String(format: "%.2f", totalCashback),
                    icon: "arrow.up.circle.fill", color: .green
                )
                .overlay(
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundColor(.gray.opacity(0.5)).padding(.trailing, 10),
                    alignment: .trailing
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top)
    }

    @ViewBuilder
    private var transactionList: some View {
        LazyVStack(spacing: 15) {
            ForEach(filteredTransactions) { item in
                VStack(alignment: .leading, spacing: 8) {
                    TransactionRow(transaction: item, exchangeRates: exchangeRates)
                        .onTapGesture { selectedTransaction = item }
                        .contextMenu {
                            Button { transactionToEdit = item } label: { Label("编辑", systemImage: "pencil") }
                            Button { incomeTargetTransaction = item } label: { Label("添加收入", systemImage: "plus.rectangle.on.rectangle") }
                            Divider()
                            Button(role: .destructive) { context.delete(item) } label: { Label("删除", systemImage: "trash") }
                        }
                    
                    // 显示关联收入
                    if let incomes = item.incomes, !incomes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(incomes.sorted(by: { $0.date > $1.date })) { income in
                                IncomeRow(income: income)
                                    .contextMenu {
                                        Button { incomeToEdit = income } label: { Label("编辑收入", systemImage: "pencil") }
                                        Button(role: .destructive) {
                                            context.delete(income)
                                            try? context.save() // 强制保存以更新 UI
                                        } label: { Label("删除", systemImage: "trash") }
                                    }
                            }
                        }
                        .padding(.leading, 30)
                    }
                }
            }
            
            // 空状态提示
            if filteredTransactions.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey(isSearchingActive ? "未找到结果" : "暂无账单"),
                    systemImage: isSearchingActive ? "magnifyingglass" : "list.bullet.clipboard",
                    description: Text(isSearchingActive ? "尝试更换关键词" : "该筛选条件下没有交易记录")
                )
                .padding(.top, 40)
            }
        }
        .padding(.horizontal)
    }
    
    // 计算总支出
    var totalExpense: Double {
        if exchangeRates.isEmpty { return 0.0 }
        return filteredTransactions.reduce(0) { total, t in
            let code = t.card?.issueRegion.currencyCode ?? "CNY"
            let rate = exchangeRates[code] ?? 1.0

            let expenseInMain = t.billingAmount / rate
            let incomeInMain = (t.incomes ?? []).reduce(0) { partial, income in
                let incomeCode = income.location.currencyCode
                let incomeRate = exchangeRates[incomeCode] ?? 1.0
                return partial + (income.amount / incomeRate)
            }

            return total + (expenseInMain - incomeInMain)
        }
    }
    
    // 计算总返现
    var totalCashback: Double {
        if exchangeRates.isEmpty { return 0.0 }
        return filteredTransactions.reduce(0) { total, t in
            let cb = CashbackService.calculateCashback(for: t)
            let code = t.card?.issueRegion.currencyCode ?? "CNY"
            let rate = exchangeRates[code] ?? 1.0
            return total + (cb / rate)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // 1. 统计条 (点击数字可查看趋势)
                        statsBar
                        
                        // 2. 控制栏 (筛选器) - 使用 ScrollView 优化布局
                        filterBar
                        
                        // 3. 交易列表
                        transactionList
                    }
                }
            }
            .navigationTitle("Cashback Counter")
            .navigationBarTitleDisplayMode(.inline)
            // 👇 新增：搜索框
            .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .automatic, prompt: "搜索全部信息")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // 导出
                        if !filteredTransactions.isEmpty,
                           let receiptsZipURL = filteredTransactions.exportReceiptsZip() {
                            ShareLink(items: [receiptsZipURL]) {
                                Label("导出账单", systemImage: "square.and.arrow.up")
                            }
                        }
                        
                        // 导入
                        Button { showFileImporter = true } label: {
                            Label("导入账单", systemImage: "square.and.arrow.down")
                        }
                        Button { showStatementAnalysis = true } label: {
                            Label("导入结单", systemImage: "chart.bar.doc.horizontal.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 18))
                    }
                }
            }

            // 文件导入器
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    do {
                        if url.pathExtension.lowercased() == "zip" {
                            try CSVHelper.importBackupZip(url: url, context: context, allCards: cards)
                            importMessage = "ZIP 备份导入成功！"
                        } else {
                            let content = try String(contentsOf: url, encoding: .utf8)
                            _ = try CSVHelper.parseTransactionCSV(content: content, context: context, allCards: cards)
                            importMessage = "CSV 导入成功！"
                        }
                        showImportAlert = true
                    } catch {
                        importMessage = "导入失败：\(error.localizedDescription)"
                        showImportAlert = true
                    }
                case .failure(let error):
                    print("选择文件失败: \(error)")
                }
            }
            .alert("导入结果", isPresented: $showImportAlert) {
                Button("确定", role: .cancel) { }
            } message: { Text(importMessage) }
            
            // 各类 Sheet 弹窗
            .sheet(item: $selectedTransaction) { item in
                TransactionDetailView(transaction: item).presentationDetents([.large])
            }
            .sheet(item: $incomeTargetTransaction) { transaction in
                AddIncomeView(transaction: transaction)
            }
            .sheet(item: $incomeToEdit) { income in
                EditIncomeView(income: income)
            }
            .sheet(item: $transactionToEdit) { item in
                AddTransactionView(transaction: item)
            }
            .sheet(isPresented: $showDatePicker) {
                MonthYearPicker(date: $selectedDate, isWholeYear: $isWholeYear)
                    .presentationDetents([.height(300)])
                    .onDisappear { withAnimation { showAll = false } }
            }
            .sheet(isPresented: $showTrendSheet) {
                TrendAnalysisView(transactions: dbTransactions, cards: cards, exchangeRates: exchangeRates, type: .cashback)
                    .presentationDetents([.large, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showExpenseSheet) {
                TrendAnalysisView(transactions: dbTransactions, cards: cards, exchangeRates: exchangeRates, type: .expense)
                    .presentationDetents([.large, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showStatementAnalysis) {
                StatementAnalysisEntryView()
            }
        }
        .task {
            do {
                let rates = await CurrencyService.getRates(base: mainCurrencyCode)
                await MainActor.run { self.exchangeRates = rates }
            }
        }
        .onChange(of: mainCurrencyCode) { _, newCode in
            Task {
                do {
                    let rates = await CurrencyService.getRates(base: newCode)
                    await MainActor.run { self.exchangeRates = rates }
                }
            }
        }
        .onAppear {
            do {
                try CardTemplate.syncDefaultTemplates(in: context)
                try CardTemplate.refreshCardsFromTemplates(in: context)
            } catch { print("Failed to sync card templates: \(error)") }
        }
    }
}

// MARK: - 抽取出的通用筛选按钮组件
struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.subheadline)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isSelected ? Color.blue : Color.clear)
        .foregroundColor(isSelected ? .white : .blue)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: 1))
    }
}
