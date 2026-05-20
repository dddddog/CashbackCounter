//
//  SettingsViewModel.swift
//  CashbackCounter
//

import SwiftUI
import SwiftData

@Observable
final class SettingsViewModel {
    // MARK: - State
    var showConfirmClear: Bool = false
    var shareData: ShareData?
    var isExporting = false

    // MARK: - Export Logic

    func startExportProcess(cards: [CreditCard], transactions: [Transaction]) {
        isExporting = true

        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)

            let items = generateExportItems(cards: cards, transactions: transactions)

            await MainActor.run {
                isExporting = false
                if !items.isEmpty {
                    shareData = ShareData(items: items)
                }
            }
        }
    }

    private func generateExportItems(cards: [CreditCard], transactions: [Transaction]) -> [Any] {
        var items: [Any] = []

        if let cardCSV = cards.exportCSVFile() {
            items.append(cardCSV)
        }

        if let backupZip = transactions.exportReceiptsZip() {
            items.append(backupZip)
        }

        return items
    }

    // MARK: - Data Reset

    func clearAllData(context: ModelContext) {
        do {
            try deleteAll(of: Transaction.self, context: context)
            try deleteAll(of: CreditCard.self, context: context)
            try context.save()
            print("✅ All data cleared")
        } catch {
            print("❌ Failed to clear data: \(error)")
        }
    }

    private func deleteAll<T>(of type: T.Type, context: ModelContext) throws where T: SwiftData.PersistentModel {
        let descriptor = SwiftData.FetchDescriptor<T>()
        let items = try context.fetch(descriptor)
        for item in items {
            context.delete(item)
        }
    }
}
