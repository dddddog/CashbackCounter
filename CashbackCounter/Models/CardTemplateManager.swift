//
//  CardTemplateManager.swift
//  CashbackCounter
//

import Foundation
import SwiftData

@Observable
final class CardTemplateManager {
    static let shared = CardTemplateManager()
    
    // 替换为你的 GitHub Raw 链接
    let remoteURL = URL(string: "https://raw.githubusercontent.com/junhaohuang/CashbackCounterConfig/main/CardTemplates.json")!
    
    var templates: [CardTemplate] = []
    
    private init() {}
    
    @MainActor
    func syncTemplates() async {
        do {
            let seeds = try await fetchTemplateSeeds()
            self.templates = seeds
        } catch {
            print("❌ Failed to sync templates: \(error)")
        }
    }
    
    private func fetchTemplateSeeds() async throws -> [CardTemplate] {
        let rawTemplates: [CardTemplate]
        // 尝试从远端获取
        do {
            var request = URLRequest(url: remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 5.0
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                rawTemplates = try decoder.decode([CardTemplate].self, from: data)
            } else {
                throw NSError(domain: "CardTemplateManager", code: 404)
            }
        } catch {
            print("⚠️ 无法从远端获取配置，尝试读取本地缓存... (\(error.localizedDescription))")
            // 远端获取失败，从本地字符串常量读取 fallback
            guard let data = defaultCardTemplatesJSON.data(using: .utf8) else {
                throw NSError(domain: "CardTemplateManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法解析本地 fallback JSON"])
            }
            let decoder = JSONDecoder()
            rawTemplates = try decoder.decode([CardTemplate].self, from: data)
        }
        
        // 返回前排好序，避免在 View 的 body 中进行耗时的重排序操作
        return rawTemplates.sorted(by: {
            $0.bankName < $1.bankName || ($0.bankName == $1.bankName && $0.type < $1.type)
        })
    }
    
    @MainActor
    func refreshCardsFromTemplates(in context: ModelContext) throws {
        let templateMap = Dictionary(self.templates.map { ($0.templateKey, $0) }, uniquingKeysWith: { first, _ in first })
        
        let pointDescriptor = FetchDescriptor<Point>()
        let currentPoints = try context.fetch(pointDescriptor)
        let pointMap = Dictionary(currentPoints.map {
            (CardTemplate.pointTemplateKey(bankName: $0.bankName, pointName: $0.pointName, currencyCode: $0.valueCurrencyCode), $0)
        }, uniquingKeysWith: { first, _ in first })

        let cards = try context.fetch(FetchDescriptor<CreditCard>())
        for card in cards {
            guard let key = card.templateKey, let template = templateMap[key] else { continue }
            template.applyRules(to: card, pointMap: pointMap)
        }
    }
}
