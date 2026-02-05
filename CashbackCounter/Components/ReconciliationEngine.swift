import Foundation

struct ReconciliationReport {
    let matched: [ImportedTransaction]
    let missingInApp: [ImportedTransaction]
}

struct ReconciliationEngine {
    func compare(imported: [ImportedTransaction], existing: [Transaction]) -> ReconciliationReport {
        let calendar = Calendar.current

        let matched = imported.filter { importedTransaction in
            existing.contains { transaction in
                amountsMatch(importedTransaction.billingAmount, transaction.billingAmount) &&
                datesWithinRange(importedTransaction.transactionDate, transaction.date, calendar: calendar)
            }
        }

        let missing = imported.filter { importedTransaction in
            !matched.contains(where: { $0.id == importedTransaction.id })
        }

        return ReconciliationReport(matched: matched, missingInApp: missing)
    }

    private func amountsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        return abs(lhs - rhs) < 0.0001
    }

    private func datesWithinRange(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        let leftDay = calendar.startOfDay(for: lhs)
        let rightDay = calendar.startOfDay(for: rhs)
        let dayDiff = calendar.dateComponents([.day], from: leftDay, to: rightDay).day ?? Int.max
        return abs(dayDiff) <= 3
    }
}
