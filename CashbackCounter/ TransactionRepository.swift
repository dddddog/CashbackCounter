// TransactionRepository.swift
import Foundation
import SwiftData

protocol TransactionRepositoryProtocol {
    //导入逻辑

    func fetchTransactions(
            date: Date,
            granularity: Calendar.Component,
            category: Category?,
            incomeOnly: Bool
        ) throws -> [Transaction]
        
        /// 范围查询：用于趋势分析 (TrendAnalysis)
        /// - Parameters:
        ///   - start: 开始时间
        ///   - end: 结束时间
    func fetchTransactions(from start: Date, to end: Date) throws -> [Transaction]
    func insert(_ transaction: Transaction)
    func delete(_ transaction: Transaction)
    func syncCardTemplates() throws
    func importData(from url: URL) throws
    // --- 信用卡相关 ---
    func fetchCards(sortBy: [SortDescriptor<CreditCard>]) throws -> [CreditCard]
    func insertCard(_ card: CreditCard)
    func deleteCard(_ card: CreditCard) // ✨ 新增
    
    func save() throws
}
