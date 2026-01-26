import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BillHomeView: View {
    // --- 1. 环境与持久化数据 ---
    @Environment(\.modelContext) var context
    
    // 使用 @Query 仅用于获取数据源，逻辑筛选交给 ViewModel
    @Query(sort: [
        SortDescriptor(\Transaction.date, order: .reverse),
        SortDescriptor(\Transaction.merchant, order: .forward)
    ])
    var dbTransactions: [Transaction]
    @State private var viewModel : BillHomeViewModel

    @Query var cards: [CreditCard]
    init(repository: TransactionRepositoryProtocol) {
        // 使用 _变量名 来初始化 @State 属性
        self._viewModel = State(initialValue: BillHomeViewModel(repository: repository))
    }
    // --- 2. ViewModel 与 持久化配置 ---
    @AppStorage("mainCurrencyCode") private var mainCurrencyCode: String = "CNY"
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. 顶部统计卡片
                        statisticsHeader
                        
                        // 2. 筛选控制栏
                        filterControlBar
                        
                        // 3. 交易账单列表
                        transactionListView
                    }
                }
            }
            .navigationTitle("Cashback Counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            
            // --- 弹窗与交互绑定 ---
            .sheet(item: $viewModel.selectedTransaction) { item in
                TransactionDetailView(transaction: item).presentationDetents([.large])
            }
            .sheet(item: $viewModel.transactionToEdit) { item in
                AddTransactionView(repository: viewModel.repository, transaction: item)
            }
            .sheet(item: $viewModel.incomeTargetTransaction) { transaction in
                AddIncomeView(transaction: transaction)
            }
            .sheet(item: $viewModel.incomeToEdit) { income in
                EditIncomeView(income: income)
            }
            .sheet(isPresented: $viewModel.showDatePicker) {
                MonthYearPicker(date: $viewModel.selectedDate, isWholeYear: $viewModel.isWholeYear)
                    .presentationDetents([.height(300)])
                    .onDisappear { withAnimation { viewModel.showAll = false } }
            }
            .sheet(isPresented: $viewModel.showTrendSheet) {
                TrendAnalysisView(transactions: dbTransactions, exchangeRates: viewModel.exchangeRates, type: .cashback)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $viewModel.showExpenseSheet) {
                TrendAnalysisView(transactions: dbTransactions, exchangeRates: viewModel.exchangeRates, type: .expense)
                    .presentationDetents([.large])
            }
            
            // --- 导入功能绑定 ---
            .fileImporter(
                isPresented: $viewModel.showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .zip],
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleImport(result: result, context: context, cards: cards)
            }
            .alert("导入结果", isPresented: $viewModel.showImportAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(viewModel.importMessage)
            }
        }
        .task {
            viewModel.mainCurrencyCode = mainCurrencyCode
            await viewModel.updateRates()
        }
        .onChange(of: mainCurrencyCode) { _, newCode in
            viewModel.mainCurrencyCode = newCode
            Task { await viewModel.updateRates() }
        }
        .onAppear {
            viewModel.syncTemplates(context: context)
        }
    }
}

// MARK: - UI 子组件 (Helper Methods)
extension BillHomeView {
    
    /// 统计概览区域
    private var statisticsHeader: some View {
        let filtered = viewModel.filteredTransactions(dbTransactions)
        let isDataLoading = viewModel.exchangeRates.isEmpty
        
        return HStack(spacing: 12) {
            // 支出卡片
            StatBox(
                title: viewModel.isWholeYear ? "本年支出" : "本月支出",
                amount: String(format: "%.2f", viewModel.calculateTotalExpense(for: filtered)),
                icon: "arrow.down.right.circle.fill",
                color: .red,
                isLoading: isDataLoading
            )
            .onTapGesture { viewModel.showExpenseSheet = true }

            // 返现卡片
            StatBox(
                title: viewModel.isWholeYear ? "本年返现" : "本月返现",
                amount: String(format: "%.2f", viewModel.calculateTotalCashback(for: filtered)),
                icon: "arrow.up.left.circle.fill",
                color: .green,
                isLoading: isDataLoading
            )
            .onTapGesture { viewModel.showTrendSheet = true }
        }
        .padding(.horizontal)
    }

    /// 筛选控制工具栏
    private var filterControlBar: some View {
        HStack(spacing: 10) {
            Spacer()
            
            // 类别筛选菜单
            Menu {
                Button(action: { viewModel.selectedCategory = nil }) {
                    Label("全部种类", systemImage: "checkmark.circle")
                }
                ForEach(Category.allCases, id: \.self) { category in
                    Button(action: { viewModel.selectedCategory = category }) {
                        Label(category.displayName, systemImage: category.iconName)
                    }
                }
            } label: {
                FilterTag(
                    icon: viewModel.selectedCategory?.iconName ?? "line.3.horizontal.decrease.circle",
                    text: viewModel.selectedCategory?.displayName ?? "全部种类",
                    isSelected: viewModel.selectedCategory != nil
                )
            }

            // 仅看收入切换
            Button(action: { viewModel.showIncomeOnly.toggle() }) {
                FilterTag(icon: "tray.and.arrow.down.fill", text: "收入单", isSelected: viewModel.showIncomeOnly)
            }

            // 日期切换按钮
            Button(action: { viewModel.showDatePicker = true }) {
                FilterTag(icon: "calendar", text: viewModel.dateButtonText, isSelected: !viewModel.showAll, activeColor: .blue)
            }
        }
        .padding(.horizontal)
    }

    /// 核心账单列表
    private var transactionListView: some View {
        let filtered = viewModel.filteredTransactions(dbTransactions)
        return LazyVStack(spacing: 15) {
            ForEach(filtered) { item in
                VStack(alignment: .leading, spacing: 8) {
                    TransactionRow(transaction: item, exchangeRates: viewModel.exchangeRates)
                        .onTapGesture { viewModel.selectedTransaction = item }
                        .contextMenu {
                            Button { viewModel.transactionToEdit = item } label: { Label("编辑", systemImage: "pencil") }
                            Button { viewModel.incomeTargetTransaction = item } label: { Label("添加收入", systemImage: "plus.rectangle.on.rectangle") }
                            Divider()
                            Button(role: .destructive) { context.delete(item) } label: { Label("删除", systemImage: "trash") }
                        }
                    
                    // 渲染关联的收入
                    if let incomes = item.incomes, !incomes.isEmpty {
                        ForEach(incomes.sorted(by: { $0.date > $1.date })) { income in
                            IncomeRow(income: income)
                                .padding(.leading, 30)
                                .contextMenu {
                                    Button { viewModel.incomeToEdit = income } label: { Label("编辑收入", systemImage: "pencil") }
                                    Button(role: .destructive) { context.delete(income) } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            
            if filtered.isEmpty {
                ContentUnavailableView("暂无账单", systemImage: "list.bullet.clipboard", description: Text("该时间段内没有交易记录"))
                    .padding(.top, 40)
            }
        }
        .padding(.horizontal)
    }

    /// 导航栏工具
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // 导出功能
                if !dbTransactions.isEmpty, let zipURL = dbTransactions.exportReceiptsZip() {
                    ShareLink(items: [zipURL]) {
                        Label("导出账单", systemImage: "square.and.arrow.up")
                    }
                }
                // 导入功能
                Button { viewModel.showFileImporter = true } label: {
                    Label("导入账单", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18))
            }
        }
    }

    private var chevronIcon: some View {
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.gray.opacity(0.5))
            .padding(.trailing, 10)
    }
}

/// 辅助小视图：筛选标签
struct FilterTag: View {
    let icon: String
    let text: String
    let isSelected: Bool
    var activeColor: Color = .blue
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.subheadline)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isSelected ? activeColor : Color.clear)
        .foregroundColor(isSelected ? .white : activeColor)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(activeColor, lineWidth: 1))
    }
}
