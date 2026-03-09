import Foundation
import SwiftData

@Model
final class PointAdjustment: Identifiable {
    @Attribute(.unique) var id: UUID
    var points: Int
    var date: Date
    @Relationship(deleteRule: .nullify) var pointProgram: Point?

    init(pointProgram: Point?, points: Int, date: Date = Date()) {
        self.id = UUID()
        self.pointProgram = pointProgram
        self.points = points
        self.date = date
    }
}
