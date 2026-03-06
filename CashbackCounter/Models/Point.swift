import Foundation
import SwiftData

@Model
final class Point: Identifiable {
    @Attribute(.unique) var id: UUID
    var bankName: String
    var pointName: String
    var pointValue: Double
    var valueCurrencyCode: Region

    init(
        bankName: String,
        pointName: String,
        pointValue: Double,
        valueCurrencyCode: Region
    ) {
        self.id = UUID()
        self.bankName = bankName
        self.pointName = pointName
        self.pointValue = pointValue
        self.valueCurrencyCode = valueCurrencyCode
    }

    var displayName: String {
        "\(bankName) \(pointName)"
    }
}

struct PointSeed {
    let bankName: String
    let pointName: String
    let pointValue: Double
    let valueCurrencyCode: Region

    var templateKey: String {
        Point.templateKey(
            bankName: bankName,
            pointName: pointName,
            currencyCode: valueCurrencyCode
        )
    }

    func makeModel() -> Point {
        Point(
            bankName: bankName,
            pointName: pointName,
            pointValue: pointValue,
            valueCurrencyCode: valueCurrencyCode
        )
    }
}

extension Point {
    static let defaultSeeds: [PointSeed] = [
        PointSeed(bankName: "HSBC", pointName: "RC", pointValue: 1.25, valueCurrencyCode: .hk),
        PointSeed(bankName: "HSBC US", pointName: "Point", pointValue: 1.0, valueCurrencyCode: .us),
        PointSeed(bankName: "ICBC ASIA", pointName: "Point", pointValue: 0.01, valueCurrencyCode: .hk),
        PointSeed(bankName: "AMEX HK", pointName: "MR", pointValue: 0.01, valueCurrencyCode: .hk),
        PointSeed(bankName: "Generic", pointName: "Standard Points (JPY)", pointValue: 0.01, valueCurrencyCode: .jp)
    ]

    static func syncDefaultPoints(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Point>()
        let currentPoints = try context.fetch(descriptor)
        let currentMap = Dictionary(uniqueKeysWithValues: currentPoints.map { (templateKey(for: $0), $0) })

        for seed in defaultSeeds where currentMap[seed.templateKey] == nil {
            context.insert(seed.makeModel())
        }
    }

    fileprivate static func templateKey(for point: Point) -> String {
        templateKey(
            bankName: point.bankName,
            pointName: point.pointName,
            currencyCode: point.valueCurrencyCode
        )
    }

    fileprivate static func templateKey(bankName: String, pointName: String, currencyCode: Region) -> String {
        let parts = [bankName, pointName, currencyCode.currencyCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return parts.joined(separator: "|")
    }
}
