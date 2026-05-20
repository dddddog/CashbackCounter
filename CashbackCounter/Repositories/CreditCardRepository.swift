//
//  CreditCardRepository.swift
//  CashbackCounter
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol CreditCardRepository {
    func fetchAll() -> [CreditCard]
    func fetchSorted(by keyPath: String) -> [CreditCard]
    func insert(_ card: CreditCard)
    func delete(_ card: CreditCard)
    func save() throws
}

// MARK: - SwiftData Implementation

@Observable
final class SwiftDataCreditCardRepository: CreditCardRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [CreditCard] {
        let descriptor = FetchDescriptor<CreditCard>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchSorted(by keyPath: String = "bankName") -> [CreditCard] {
        let descriptor = FetchDescriptor<CreditCard>(
            sortBy: [SortDescriptor(\CreditCard.bankName)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func insert(_ card: CreditCard) {
        modelContext.insert(card)
    }

    func delete(_ card: CreditCard) {
        modelContext.delete(card)
    }

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
