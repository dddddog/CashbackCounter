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
        predicate: Predicate<Transaction>? = nil,
        sortBy: [SortDescriptor<Transaction>] = [SortDescriptor(\.date, order: .reverse)]
    ) throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(predicate: predicate, sortBy: sortBy)
        return try context.fetch(descriptor)
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
