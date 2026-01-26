// TransactionRepository.swift
import Foundation
import SwiftData

protocol TransactionRepositoryProtocol {
    //导入逻辑

    func fetchTransactions(predicate: Predicate<Transaction>?, sortBy: [SortDescriptor<Transaction>]) throws -> [Transaction]
    func insert(_ transaction: Transaction)
    func delete(_ transaction: Transaction)
    
    // --- 信用卡相关 ---
    func fetchCards(sortBy: [SortDescriptor<CreditCard>]) throws -> [CreditCard]
    func insertCard(_ card: CreditCard)
    func deleteCard(_ card: CreditCard) // ✨ 新增
    
    func save() throws
}
