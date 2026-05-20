import Foundation
import SwiftData

// MARK: - 积分调整类型
enum AdjustmentType: String, Codable, CaseIterable {
    case earn       // 消费获得
    case redeem     // 兑换使用
    case expire     // 积分过期
    case transfer   // 积分转移
    case bonus      // 活动赠送 / 开卡奖励
    case manual     // 手动调整

    var displayName: String {
        switch self {
        case .earn:     return "消费获得"
        case .redeem:   return "兑换使用"
        case .expire:   return "积分过期"
        case .transfer: return "积分转移"
        case .bonus:    return "活动赠送"
        case .manual:   return "手动调整"
        }
    }

    var iconName: String {
        switch self {
        case .earn:     return "plus.circle.fill"
        case .redeem:   return "gift.fill"
        case .expire:   return "clock.badge.xmark"
        case .transfer: return "arrow.left.arrow.right"
        case .bonus:    return "star.fill"
        case .manual:   return "pencil.circle.fill"
        }
    }
}

@Model
final class PointAdjustment: Identifiable {
    @Attribute(.unique) var id: UUID
    var points: Int
    var date: Date
    var type: AdjustmentType = AdjustmentType.manual
    var note: String = ""
    var pointProgram: Point?

    init(pointProgram: Point?, points: Int, date: Date = Date(), type: AdjustmentType = .manual, note: String = "") {
        self.id = UUID()
        self.pointProgram = pointProgram
        self.points = points
        self.date = date
        self.type = type
        self.note = note
    }
}
