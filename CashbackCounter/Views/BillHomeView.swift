import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BillHomeView: View {
    // --- 1. 核心变化：移除 @Query 和 @Environment(\.modelContext) ---
    // 改为持有 ViewModel
    @State private var viewModel: BillHomeViewModel

    // 初始化时注入仓库
    init(repository: TransactionRepositoryProtocol) {
        _viewModel = State(initialValue: BillHomeViewModel(repository: repository))
    }
    
    // 保留原本的 AppStorage
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
            
            // --- 弹窗与交互绑定 (完全保留) ---
            .sheet(item: $viewModel.selectedTransaction) { item in
                TransactionDetailView(transaction: item).presentationDetents([.large])
            }
            // 注意：这里传递 repository 给 AddTransactionView
            .sheet(item: $viewModel.transactionToEdit) { item in
                AddTransactionView(repository: viewModel.repository, transaction: item)
                    .onDisappear { viewModel.loadTransactions() } // 编辑回来刷新
            }
            .sheet(item: $viewModel.incomeTargetTransaction) { transaction in
                AddIncomeView(transaction: transaction)
                    .onDisappear { viewModel.loadTransactions() } // 添加收入回来刷新
            }
            .sheet(item: $viewModel.incomeToEdit) { income in
                EditIncomeView(income: income)
                    .onDisappear { viewModel.loadTransactions() }
            }
            .sheet(isPresented: $viewModel.showDatePicker) {
                MonthYearPicker(date: $viewModel.selectedDate, isWholeYear: $viewModel.isWholeYear)
                    .presentationDetents([.height(300)])
                    .onDisappear {
                        withAnimation { viewModel.showAll = false }
                        // 日期选完后刷新数据
                        viewModel.loadTransactions()
                    }
            }
            // 趋势分析：暂时传入当前列表数据
            // 注意：如果 TrendAnalysisView 需要全量数据，后续可能需要让它自己去加载
            .sheet(isPresented: $viewModel.showTrendSheet) {
                TrendAnalysisView(transactions: viewModel.transactions, exchangeRates: viewModel.exchangeRates, type: .cashback)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $viewModel.showExpenseSheet) {
                TrendAnalysisView(transactions: viewModel.transactions, exchangeRates: viewModel.exchangeRates, type: .expense)
                    .presentationDetents([.large])
            }
            
            // --- 导入功能绑定 ---
            .fileImporter(
                isPresented: $viewModel.showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .zip],
                allowsMultipleSelection: false
            ) { result in
                // 修改：不需要传 context 和 cards 了，ViewModel 内部处理
                viewModel.handleImport(result: result)
            }
            .alert("导入结果", isPresented: $viewModel.showImportAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(viewModel.importMessage)
            }
            // 错误提示
            .alert("错误", isPresented: $viewModel.showErrorAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
        }
        // --- 生命周期与数据加载 ---
        .task {
            viewModel.mainCurrencyCode = mainCurrencyCode
            await viewModel.updateRates()
            viewModel.loadTransactions() // 首次加载
        }
        .onChange(of: mainCurrencyCode) { _, newCode in
            viewModel.mainCurrencyCode = newCode
            Task { await viewModel.updateRates() }
        }
        // 监听筛选条件变化自动刷新
        .onChange(of: viewModel.selectedCategory) { _, _ in viewModel.loadTransactions() }
        .onChange(of: viewModel.showIncomeOnly) { _, _ in viewModel.loadTransactions() }
        // 每次显示时（例如从子页面回来）刷新数据
        .onAppear {
            viewModel.syncTemplates() // 不需要 context
            viewModel.loadTransactions()
        }
    }
}

// MARK: - UI 子组件 (Helper Methods)
extension BillHomeView {
    
    /// 统计概览区域
    private var statisticsHeader: some View {
        // 修改：直接使用 viewModel.transactions，它已经是筛选过的了
        // 原来的逻辑是 filteredTransactions(dbTransactions)，现在 VM 已经做好了
        let isDataLoading = viewModel.exchangeRates.isEmpty
        
        return HStack(spacing: 12) {
            // 支出卡片
            StatBox(
                title: viewModel.isWholeYear ? "本年支出" : "本月支出",
                amount: String(format: "%.2f", viewModel.totalExpense), // 使用 ViewModel 新增的计算属性
                icon: "arrow.down.right.circle.fill",
                color: .red,
                isLoading: isDataLoading
            )
            .onTapGesture { viewModel.showExpenseSheet = true }

            // 返现卡片
            StatBox(
                title: viewModel.isWholeYear ? "本年返现" : "本月返现",
                amount: String(format: "%.2f", viewModel.totalCashback), // 使用 ViewModel 新增的计算属性
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
        // 修改：直接使用 viewModel.transactions
        let filtered = viewModel.transactions
        
        return LazyVStack(spacing: 15) {
            ForEach(filtered) { item in
                VStack(alignment: .leading, spacing: 8) {
                    TransactionRow(transaction: item, exchangeRates: viewModel.exchangeRates)
                        .onTapGesture { viewModel.selectedTransaction = item }
                        .contextMenu {
                            Button { viewModel.transactionToEdit = item } label: { Label("编辑", systemImage: "pencil") }
                            Button { viewModel.incomeTargetTransaction = item } label: { Label("添加收入", systemImage: "plus.rectangle.on.rectangle") }
                            Divider()
                            // 修改：调用 ViewModel 删除
                            Button(role: .destructive) { viewModel.deleteTransaction(item) } label: { Label("删除", systemImage: "trash") }
                        }
                    
                    // 渲染关联的收入
                    if let incomes = item.incomes, !incomes.isEmpty {
                        ForEach(incomes.sorted(by: { $0.date > $1.date })) { income in
                            IncomeRow(income: income)
                                .padding(.leading, 30)
                                .contextMenu {
                                    Button { viewModel.incomeToEdit = income } label: { Label("编辑收入", systemImage: "pencil") }
                                    // ⚠️ 如果你还没有实现 deleteIncome，可以用 deleteTransaction 替代，或者在 VM 里加一个方法
                                    Button(role: .destructive) {
                                        // 假设暂时借用删除交易的逻辑，或者你需要补上 deleteIncome
                                        // viewModel.deleteIncome(income)
                                    } label: { Label("删除", systemImage: "trash") }
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
                // 修改：使用 viewModel.transactions
                if !viewModel.transactions.isEmpty, let zipURL = viewModel.transactions.exportReceiptsZip() {
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
}

// MARK: - FilterTag 必须放在最外层，不能放在 extension 里
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
