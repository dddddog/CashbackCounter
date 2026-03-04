import Foundation
import SwiftData

@Model
final class Point: Identifiable {
    @Attribute(.unique) var id: UUID
    var bankName: String
    var pointName: String
    var pointValue: Double
    var exchangeRate: Int
    var valueCurrencyCode: String
    init(
        bankName: String,
        pointName: String,
        pointValue: Double,
        exchangeRate: Int,
        valueCurrencyCode: String
    ) {
        self.id = UUID()
        self.bankName = bankName
        self.pointName = pointName
        self.pointValue = pointValue
        self.exchangeRate = exchangeRate
        self.valueCurrencyCode = valueCurrencyCode
    }

    var displayName: String {
        "\(bankName) \(pointName)"
    }
}
