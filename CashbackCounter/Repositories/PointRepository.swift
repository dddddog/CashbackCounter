//
//  PointRepository.swift
//  CashbackCounter
//

import Foundation
import SwiftData

// MARK: - Protocol

protocol PointRepository {
    func fetchAll() -> [Point]
    func fetchSorted() -> [Point]
    func fetchAllAdjustments() -> [PointAdjustment]
    func insert(_ point: Point)
    func delete(_ point: Point)
    func insertAdjustment(_ adjustment: PointAdjustment)
    func deleteAdjustment(_ adjustment: PointAdjustment)
    func save() throws
    func syncDefaultPoints() throws
}

// MARK: - SwiftData Implementation

@Observable
final class SwiftDataPointRepository: PointRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() -> [Point] {
        let descriptor = FetchDescriptor<Point>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchSorted() -> [Point] {
        let descriptor = FetchDescriptor<Point>(
            sortBy: [SortDescriptor(\Point.bankName)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchAllAdjustments() -> [PointAdjustment] {
        let descriptor = FetchDescriptor<PointAdjustment>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func insert(_ point: Point) {
        modelContext.insert(point)
    }

    func delete(_ point: Point) {
        modelContext.delete(point)
    }

    func insertAdjustment(_ adjustment: PointAdjustment) {
        modelContext.insert(adjustment)
    }

    func deleteAdjustment(_ adjustment: PointAdjustment) {
        modelContext.delete(adjustment)
    }

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func syncDefaultPoints() throws {
        try Point.syncDefaultPoints(in: modelContext)
    }
}
