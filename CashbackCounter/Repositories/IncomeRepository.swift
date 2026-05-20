//
//  IncomeRepository.swift
//  CashbackCounter
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol IncomeRepository {
    func fetchAll() -> [Income]
    func insert(_ income: Income)
    func delete(_ income: Income)
    func save() throws
}

// MARK: - SwiftData Implementation

@Observable
final class SwiftDataIncomeRepository: IncomeRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [Income] {
        let descriptor = FetchDescriptor<Income>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func insert(_ income: Income) {
        modelContext.insert(income)
    }

    func delete(_ income: Income) {
        modelContext.delete(income)
    }

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
