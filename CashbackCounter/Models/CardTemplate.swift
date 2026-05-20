//
//  CardTemplate.swift
//  CashbackCounter
//

import SwiftUI
import SwiftData

struct CardTemplate: Identifiable, Codable, Hashable {
    static func templateKey(bankName: String, type: String) -> String {
        "\(bankName)-\(type)"
    }
    
    var id: UUID = UUID()
    
    let bankName: String
    let type: String
    let colors: [String]
    let region: Region
    
    let specialRate: [Category: Double]
    var paymentMethodRates: [PaymentMethod: Double] = [:]
    
    var rewardType: RewardType = .cashback
    var pointProgramKey: String? = nil
    
    let defaultRate: Double
    let foreignCurrencyRate: Double?
    var localBaseCap: Double = 0
    var foreignBaseCap: Double = 0
    var categoryCaps: [Category: Double] = [:]
    var paymentCaps: [PaymentMethod: Double] = [:]
    var capPeriod: CapPeriod = .yearly
    var pictureURL: String? = nil

    var templateKey: String { Self.templateKey(bankName: bankName, type: type) }

    enum CodingKeys: String, CodingKey {
        case bankName, type, colors, region, specialRate, paymentMethodRates, rewardType, pointProgramKey, defaultRate, foreignCurrencyRate, localBaseCap, foreignBaseCap, categoryCaps, paymentCaps, capPeriod, pictureURL
    }

    static func pointTemplateKey(bankName: String, pointName: String, currencyCode: Region) -> String {
        let parts = [bankName, pointName, currencyCode.currencyCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return parts.joined(separator: "|")
    }

    func applyRules(to card: CreditCard, pointMap: [String: Point]) {
        card.bankName = bankName
        card.type = type
        card.colorHexes = colors
        card.issueRegion = region
        
        card.specialRates = Dictionary(uniqueKeysWithValues: specialRate.map { ($0.key, $0.value / 100.0) })
        card.paymentMethodRates = Dictionary(uniqueKeysWithValues: paymentMethodRates.map { ($0.key, $0.value / 100.0) })

        card.rewardType = rewardType
        if let pointProgramKey {
            card.pointProgram = pointMap[pointProgramKey]
        } else {
            card.pointProgram = nil
        }

        card.defaultRate = defaultRate / 100.0
        card.foreignCurrencyRate = foreignCurrencyRate.map { $0 / 100.0 }
        
        card.localBaseCap = localBaseCap
        card.foreignBaseCap = foreignBaseCap
        card.categoryCaps = categoryCaps
        card.paymentCaps = paymentCaps
        
        card.capPeriod = capPeriod
        card.templateKey = templateKey
        if let source = pictureURL {
            Task {
                if let data = await ImageDownloadManager.shared.downloadImageData(from: source) {
                    await MainActor.run {
                        withAnimation {
                            card.cardImageData = data
                        }
                    }
                }
            }
        }
    }
}
