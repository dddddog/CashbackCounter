// SwiftDataTransactionRepository.swift
import Foundation
import SwiftData

class TransactionRepository: TransactionRepositoryProtocol {
    
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }
    
    /// 获取账单数据
    func fetchTransactions(
            date: Date,
            granularity: Calendar.Component,
            category: Category?,
            incomeOnly: Bool
    ) throws -> [Transaction] {
        // 1. 计算时间范围
        let calendar = Calendar.current
        let startDate = calendar.dateInterval(of: granularity, for: date)?.start ?? date
        let endDate = calendar.dateInterval(of: granularity, for: date)?.end ?? date
        
        // 2. 注意：SwiftData 的 Predicate 构建目前比较严格，有时不支持过于复杂的嵌套。
        // 为了稳健性，通常建议先在数据库层做主要过滤（时间），然后在内存做次要过滤（如复杂关联），
        // 或者构建多个 Predicate。
        
        // 构建时间范围的 Predicate
        // 注意：SwiftData Predicate 宏不仅不能捕获外部变量（需要传值），对 Optionals 的支持也有限。
        // 这里演示一个标准的“获取所有后筛选”或“构建基础 Predicate”的方法。
        
        // 方案 A：直接使用 FetchDescriptor 配合 Predicate (最理想，但需小心崩溃)
        // 由于 Category 是 Enum，SwiftData 支持比较。
        
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { t in
                t.date >= startDate && t.date < endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        var results = try context.fetch(descriptor)
        
        // 3. 在内存中应用剩余过滤 (SwiftData 对关联属性 incomes 的查询支持尚不完美)
        if let category = category {
            results = results.filter { $0.category == category }
        }
        
        if incomeOnly {
            results = results.filter { ($0.incomes?.isEmpty == false) } // 假设 incomes 是数组
        }
        
        return results
    }
        
    func fetchTransactions(from start: Date, to end: Date) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { t in
                t.date >= start && t.date <= end
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
    // 同步卡
    func syncCardTemplates() throws {
        // 直接使用类内部持有的 context，不需要从外部传参
        try CardTemplate.syncDefaultTemplates(in: context)
        try CardTemplate.refreshCardsFromTemplates(in: context)
        
        // 可选：同步完立即保存，或者留给调用者决定
        try save()
    }
    //导入账单
    func importData(from url: URL) throws {
            // 1. 准备工作：CSVHelper 解析时通常需要匹配现有的信用卡
            //    所以我们需要先从数据库获取所有卡片
            let cardDescriptor = FetchDescriptor<CreditCard>()
            let allCards = try context.fetch(cardDescriptor)
            
            // 2. 判断文件类型
            let fileExtension = url.pathExtension.lowercased()
            
            if fileExtension == "zip" {
                // 3a. 处理 ZIP 备份文件
                // 注意：CSVHelper.importBackupZip 内部需要 context 来做插入操作
                try CSVHelper.importBackupZip(url: url, context: context, allCards: allCards)
                
            } else {
                // 3b. 处理普通 CSV 文件
                // 先读取文件内容字符串
                let content = try String(contentsOf: url, encoding: .utf8)
                
                // 解析并插入
                _ = try CSVHelper.parseTransactionCSV(content: content, context: context, allCards: allCards)
            }
            
            // 4. 强制保存
            // 虽然 CSVHelper 内部可能也会 save，但在 Repository 层显式调用一次是个好习惯，确保事务完整
            try context.save()
        }
    /// 插入新账单
    func insert(_ transaction: Transaction) {
        context.insert(transaction)
    }

    /// 删除账单
    func delete(_ transaction: Transaction) {
        context.delete(transaction)
    }

    /// 强制执行保存 (SwiftData 虽然会自动保存，但显式调用更安全)
    func save() throws {
        try context.save()
    }
    
    func fetchCards(sortBy: [SortDescriptor<CreditCard>] = [SortDescriptor(\.bankName)]) throws -> [CreditCard] {
        let descriptor = FetchDescriptor<CreditCard>(sortBy: sortBy)
        return try context.fetch(descriptor)
    }

    func insertCard(_ card: CreditCard) {
        context.insert(card)
    }

        /// ✨ 实现删除卡片逻辑
    func deleteCard(_ card: CreditCard) {
        context.delete(card)
        NotificationManager.shared.cancelNotification(for: card)
    }
}
