//
//  TransactionRepository.swift
//  CashbackCounter
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol TransactionRepository {
    func fetchAll() -> [Transaction]
    func fetchSorted(by sortOrder: SortOrder) -> [Transaction]
    func fetchForCard(_ card: CreditCard) -> [Transaction]
    func insert(_ transaction: Transaction)
    func delete(_ transaction: Transaction)
    func save() throws
}

// MARK: - SwiftData Implementation

@Observable
final class SwiftDataTransactionRepository: TransactionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchSorted(by sortOrder: SortOrder = .reverse) -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\Transaction.date, order: sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchForCard(_ card: CreditCard) -> [Transaction] {
        let allTransactions = fetchAll()
        return allTransactions.filter { $0.card?.persistentModelID == card.persistentModelID }
    }

    func insert(_ transaction: Transaction) {
        modelContext.insert(transaction)
    }

    func delete(_ transaction: Transaction) {
        modelContext.delete(transaction)
    }

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
