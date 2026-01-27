//
//  BillHomeViewModel.swift
//  CashbackCounter
//
//  Created by [Your Name] on [Date].
//

import Foundation
import SwiftUI // 为了使用 UIImage, Color 等 UI 相关类型，虽然纯 ViewModel 最好不引 SwiftUI，但在 iOS 开发中为了方便通常允许

@Observable
class BillHomeViewModel {
    
    // MARK: - 0. 核心依赖与数据源
    let repository: TransactionRepositoryProtocol
    
    /// View 监听的数据源
    var transactions: [Transaction] = []
    
    /// 错误处理
    var errorMessage: String?
    var showErrorAlert = false

    init(repository: TransactionRepositoryProtocol) {
        self.repository = repository
    }
    
    // MARK: - 1. 筛选状态 (Filtering State)
    var selectedDate = Date()
    var isWholeYear = false
    var showAll = false
    var selectedCategory: Category? = nil
    var showIncomeOnly = false
    
    // MARK: - 2. 交互与弹窗状态 (Interaction State)
    var selectedTransaction: Transaction? = nil
    var transactionToEdit: Transaction?
    var incomeTargetTransaction: Transaction?
    var incomeToEdit: Income?
    
    var showDatePicker = false
    var showTrendSheet = false
    var showExpenseSheet = false
    
    // 添加交易的 Sheet 控制
    var showAddSheet = false
    
    // MARK: - 3. 导入导出状态 (Import/Export State)
    var showFileImporter = false
    var showImportAlert = false
    var importMessage = ""
    
    // MARK: - 4. 数据支持 (Data Support)
    var exchangeRates: [String: Double] = [:]
    var mainCurrencyCode: String = "CNY"

    // MARK: - 5. 核心逻辑：数据加载 (Data Loading)
    
    /// 根据当前 UI 状态从 Repository 获取数据
    func loadTransactions() {
        do {
            let granularity: Calendar.Component = isWholeYear ? .year : .month
            
            // 调用 Repository 的高级查询方法
            let results = try repository.fetchTransactions(
                date: selectedDate,
                granularity: granularity,
                category: selectedCategory,
                incomeOnly: showIncomeOnly
            )
            
            // 更新 UI
            self.transactions = results
            
        } catch {
            print("加载失败: \(error)")
            self.errorMessage = "无法加载账单：\(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }

    // MARK: - 6. 核心逻辑：统计计算 (Statistics)
    
    /// 计算总支出 (基于当前列表数据)
    var totalExpense: Double {
        calculateTotalExpense(for: transactions)
    }
    
    /// 计算总返现 (基于当前列表数据)
    var totalCashback: Double {
        calculateTotalCashback(for: transactions)
    }

    private func calculateTotalExpense(for transactions: [Transaction]) -> Double {
        guard !exchangeRates.isEmpty else { return 0.0 }
        
        return transactions.reduce(0) { total, t in
            let code = t.card?.issueRegion.currencyCode ?? "CNY"
            let rate = exchangeRates[code] ?? 1.0
            
            // 计算支出（原币转主币）
            let expenseInMain = t.billingAmount / rate

            // 计算该交易下的收入抵扣（原币转主币）
            let incomeInMain = (t.incomes ?? []).reduce(0) { partial, income in
                let incomeRate = exchangeRates[income.location.currencyCode] ?? 1.0
                return partial + (income.amount / incomeRate)
            }

            return total + (expenseInMain - incomeInMain)
        }
    }

    private func calculateTotalCashback(for transactions: [Transaction]) -> Double {
        guard !exchangeRates.isEmpty else { return 0.0 }
        
        return transactions.reduce(0) { total, t in
            let cb = CashbackService.calculateCashback(for: t)
            let code = t.card?.issueRegion.currencyCode ?? "CNY"
            let rate = exchangeRates[code] ?? 1.0
            return total + (cb / rate)
        }
    }

    // MARK: - 7. 业务操作 (Actions)
    
    func deleteTransaction(_ item: Transaction) {
        // 1. 调用仓库删除
        repository.delete(item)
        
        // 2. 尝试保存
        do {
            try repository.save()
            // 3. 成功后，手动从内存数组移除以更新 UI (比重新查库更高效)
            if let index = transactions.firstIndex(where: { $0.id == item.id }) {
                transactions.remove(at: index)
            }
        } catch {
            print("删除失败: \(error)")
            errorMessage = "删除失败：\(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    /// 同步卡片模板
    func syncTemplates() {
        do {
            // ✅ 修改：不再传入 context，而是调用 repository 的方法
            try repository.syncCardTemplates()
        } catch {
            print("模板同步失败: \(error)")
        }
    }
    
    /// 异步更新汇率
    func updateRates() async {
        do {
            // 假设 CurrencyService 是一个独立的网络服务
            let rates = await CurrencyService.getRates(base: mainCurrencyCode)
            await MainActor.run {
                self.exchangeRates = rates
                // 汇率更新后，可能需要重新计算显示的金额，可以触发一下 UI 刷新
                // 由于 totalExpense 是计算属性，View 只要重绘就会重新计算
            }
        } catch {
            print("汇率获取失败：\(error)")
        }
    }

    // MARK: - 8. 导入逻辑 (Import Logic)
    
    /// 处理文件导入回调结果
    /// - Parameter result: 文件选择器的结果
    func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // 安全访问资源
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                // ✅ 修改：将文件处理逻辑下沉到 Repository
                // Repository 需要实现 importFile(url: URL) 方法
                // 该方法内部会判断 zip 还是 csv，并使用 Context 进行插入
                
                // 这里我们假设 Repository 还没实现那么复杂的通用导入，
                // 我们可以先调用 Repository 的 batchInsert 方法，
                // 但解析逻辑 (CSVHelper) 最好还是放在 ViewModel 或 Service 中。
                
                // 临时方案：如果 Repository 没有暴露 Context，
                // 你需要在 Repository 中添加一个专门的方法：
                // repository.importTransactions(from: url)
                
                // 假设我们在 Repository 协议中加了这个方法：
                try repository.importData(from: url)
                
                importMessage = "导入成功！"
                showImportAlert = true
                
                // 导入完成后刷新列表
                loadTransactions()
                
            } catch {
                importMessage = "导入失败：\(error.localizedDescription)"
                showImportAlert = true
            }
            
        case .failure(let error):
            print("文件选择失败: \(error)")
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
    
    // MARK: - 辅助属性
    
    var dateButtonText: String {
        if isWholeYear {
            return selectedDate.formatted(.dateTime.year()) + " 全年"
        } else {
            return selectedDate.formatted(.dateTime.year().month())
        }
    }
}
