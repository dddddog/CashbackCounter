import Foundation
import SwiftData

@Model
final class Point: Identifiable {
    @Attribute(.unique) var id: UUID
    var bankName: String
    var pointName: String
    var pointValue: Double
    var valueCurrencyCode: Region

    // 元信息
    var isActive: Bool = true
    var createdAt: Date = Date()
    var note: String = ""

    // 反向关系：哪些信用卡使用了这个积分计划
    // 删除 Point 时，卡的 pointProgram 设为 nil
    @Relationship(deleteRule: .nullify, inverse: \CreditCard.pointProgram)
    var cards: [CreditCard]?

    // 反向关系：关联的积分调整记录
    // 删除 Point 时，关联的调整记录一并删除
    @Relationship(deleteRule: .cascade, inverse: \PointAdjustment.pointProgram)
    var adjustments: [PointAdjustment]?

    // 反向关系：哪些卡片模板使用了这个积分计划
    // 删除 Point 时，模板的 pointProgram 设为 nil
    @Relationship(deleteRule: .nullify, inverse: \CardTemplate.pointProgram)
    var templates: [CardTemplate]?

    init(
        bankName: String,
        pointName: String,
        pointValue: Double,
        valueCurrencyCode: Region,
        isActive: Bool = true,
        note: String = ""
    ) {
        self.id = UUID()
        self.bankName = bankName
        self.pointName = pointName
        self.pointValue = pointValue
        self.valueCurrencyCode = valueCurrencyCode
        self.isActive = isActive
        self.createdAt = Date()
        self.note = note
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
        PointSeed(bankName: "HSBC HK", pointName: "RC", pointValue: 1.25, valueCurrencyCode: .hk),
        PointSeed(bankName: "HSBC US", pointName: "Point", pointValue: 0.015, valueCurrencyCode: .us),
        PointSeed(bankName: "BEA HK", pointName: "Point", pointValue: 0.01, valueCurrencyCode: .hk),
        PointSeed(bankName: "CCB HK", pointName: "Point", pointValue: 0.006, valueCurrencyCode: .hk),
        PointSeed(bankName: "Chase", pointName: "UR", pointValue: 0.015, valueCurrencyCode: .us),
        PointSeed(bankName: "AMEX HK", pointName: "MR", pointValue: 0.0056, valueCurrencyCode: .hk),
        PointSeed(bankName: "AMEX US", pointName: "MR", pointValue: 0.016, valueCurrencyCode: .us),
        PointSeed(bankName: "Marriott", pointName: "Point", pointValue: 0.007, valueCurrencyCode: .us),
        PointSeed(bankName: "Hilton", pointName: "Point", pointValue: 0.004, valueCurrencyCode: .us),


        
    ]

    static func syncDefaultPoints(in context: ModelContext) throws {
            let descriptor = FetchDescriptor<Point>()
            let currentPoints = try context.fetch(descriptor)
            
            // 改进 1：安全地构建字典，防止重复 Key 导致崩溃闪退
            let currentMap = Dictionary(
                currentPoints.map { (templateKey(for: $0), $0) },
                uniquingKeysWith: { (existing, _) in existing } // 如果发现重复，保留已存在的第一条
            )

            var hasChanges = false

            for seed in defaultSeeds {
                let key = seed.templateKey
                
                if let existingPoint = currentMap[key] {
                    // 改进 2：业务逻辑扩展 - 同步默认值的更新（例如积分价值改变）
                    // 如果 CashbackCounter 允许用户自定义修改这些默认积分的值，那么这里可能需要更复杂的判断
                    // 但如果是纯只读的全局基准价值，应该用以下代码覆盖更新：
                    if existingPoint.pointValue != seed.pointValue {
                        existingPoint.pointValue = seed.pointValue
                        hasChanges = true
                    }
                } else {
                    // 改进 3：插入全新缺失的数据
                    context.insert(seed.makeModel())
                    hasChanges = true
                }
            }

            // 改进 4：有实质性变更时才显式落盘，保证数据安全
            if hasChanges {
                if context.hasChanges {
                    try context.save()
                }
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
