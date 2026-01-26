import SwiftUI
import SwiftData

@Observable
class BillHomeViewModel {
    let repository: TransactionRepositoryProtocol
    init(repository: TransactionRepositoryProtocol) {
        self.repository = repository
    }
    // --- 1. 筛选状态 (Filtering State) ---
    var selectedDate = Date()
    var isWholeYear = false
    var showAll = false
    var selectedCategory: Category? = nil
    var showIncomeOnly = false
    
    // --- 2. 交互与弹窗状态 (Interaction State) ---
    var selectedTransaction: Transaction? = nil
    var transactionToEdit: Transaction?
    var incomeTargetTransaction: Transaction?
    var incomeToEdit: Income?
    var showDatePicker = false
    var showTrendSheet = false
    var showExpenseSheet = false
    
    // --- 3. 导入导出状态 (Import/Export State) ---
    var showFileImporter = false
    var showImportAlert = false
    var importMessage = ""
    
    // --- 4. 数据支持 (Data Support) ---
    var exchangeRates: [String: Double] = [:]
    var mainCurrencyCode: String = "CNY"

    // --- 5. 核心逻辑：数据筛选 (Core Filtering) ---
    /// 根据当前 UI 状态对原始数据库数组进行过滤
    func filteredTransactions(_ dbTransactions: [Transaction]) -> [Transaction] {
        var results = showAll ? dbTransactions : dbTransactions.filter { t in
            if isWholeYear {
                // 按年筛选
                return Calendar.current.isDate(t.date, equalTo: selectedDate, toGranularity: .year)
            } else {
                // 按月筛选
                return Calendar.current.isDate(t.date, equalTo: selectedDate, toGranularity: .month)
            }
        }

        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }

        if showIncomeOnly {
            results = results.filter { ($0.incomes?.isEmpty == false) }
        }

        return results
    }

    // --- 6. 核心逻辑：统计计算 (Statistics) ---
    /// 计算总支出 (已扣除收入，并自动处理多币种汇率转换)
    func calculateTotalExpense(for transactions: [Transaction]) -> Double {
        guard !exchangeRates.isEmpty else { return 0.0 }
        return transactions.reduce(0) { total, t in
            let code = t.card?.issueRegion.currencyCode ?? "CNY"
            let rate = exchangeRates[code] ?? 1.0
            let expenseInMain = t.billingAmount / rate

            // 汇总该交易下的所有收入金额
            let incomeInMain = (t.incomes ?? []).reduce(0) { partial, income in
                let incomeRate = exchangeRates[income.location.currencyCode] ?? 1.0
                return partial + (income.amount / incomeRate)
            }

            return total + (expenseInMain - incomeInMain)
        }
    }

    /// 计算总返现 (自动处理汇率转换)
    func calculateTotalCashback(for transactions: [Transaction]) -> Double {
        guard !exchangeRates.isEmpty else { return 0.0 }
        return transactions.reduce(0) { total, t in
            let cb = CashbackService.calculateCashback(for: t)
            let code = t.card?.issueRegion.currencyCode ?? "CNY"
            let rate = exchangeRates[code] ?? 1.0
            return total + (cb / rate)
        }
    }

    // --- 7. 辅助属性与方法 ---
    var dateButtonText: String {
        if isWholeYear {
            return selectedDate.formatted(.dateTime.year()) + " 全年"
        } else {
            return selectedDate.formatted(.dateTime.year().month())
        }
    }

    /// 异步更新汇率
    func updateRates() async {
        do {
            let rates = await CurrencyService.getRates(base: mainCurrencyCode)
            await MainActor.run {
                self.exchangeRates = rates
            }
        } catch {
            print("汇率获取失败：\(error)")
        }
    }
    func deleteTransaction(_ item: Transaction) {
        // 在这里可以做更多事情：
        // - 埋点：Analytics.log("delete_transaction")
        // - 检查：if item.amount > 10000 { ... }
        
        repository.delete(item)
        
        // 3. 处理保存和错误
        do {
            try repository.save()
        } catch {
            print("删除失败: \(error)")
            // 这里可以设置一个 errorMessage 属性，让 View 弹窗
        }
    }

    /// 同步卡片模板 (通常在 onAppear 调用)
    func syncTemplates(context: ModelContext) {
        do {
            try CardTemplate.syncDefaultTemplates(in: context)
            try CardTemplate.refreshCardsFromTemplates(in: context)
        } catch {
            print("模板同步失败: \(error)")
        }
    }

    // --- 8. 处理导入逻辑 (Import Logic) ---
    /// 处理文件导入回调结果
    func handleImport(result: Result<[URL], Error>, context: ModelContext, cards: [CreditCard]) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // 安全访问安全域资源 (Security Scoped Resource)
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                if url.pathExtension.lowercased() == "zip" {
                    // 处理 ZIP 备份导入
                    try CSVHelper.importBackupZip(url: url, context: context, allCards: cards)
                    importMessage = "ZIP 备份导入成功！"
                } else {
                    // 处理普通 CSV 导入
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
            print("文件选择失败: \(error)")
        }
    }
}
