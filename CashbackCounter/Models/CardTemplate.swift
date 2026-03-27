//
//  CardTemplate.swift
//  CashbackCounter
//
//  Created by OpenAI Assistant on 2024-05-28.
//

import SwiftUI
import SwiftData
import UIKit

@Model
final class CardTemplate: Identifiable {
    static func templateKey(bankName: String, type: String) -> String {
        "\(bankName)-\(type)"
    }

    @Attribute(.unique) var templateKey: String
    var id: UUID = UUID()
    var bankName: String
    var type: String
    var colors: [String]
    var region: Region
    
    // 类别加成 (存储百分比，如 5.0 代表 5%)
    var specialRate: [Category: Double]
    
    // 👇 新增：支付方式加成 (存储百分比，如 1.0 代表 Apple Pay +1%)
    var paymentMethodRates: [PaymentMethod: Double]

    var rewardType: RewardType
    var pointProgram: Point?

    var defaultRate: Double
    var foreignCurrencyRate: Double?
    
    var localBaseCap: Double
    var foreignBaseCap: Double
    var categoryCaps: [Category: Double]
    
    // 👇 新增：支付方式上限
    var paymentCaps: [PaymentMethod: Double]
    
    var capPeriod: CapPeriod
    var pictureURL: String?
    
    func applyRules(to card: CreditCard) {
        card.bankName = bankName
        card.type = type
        card.colorHexes = colors
        card.issueRegion = region
        
        // 转换百分比 (5.0 -> 0.05)
        card.specialRates = Dictionary(uniqueKeysWithValues: specialRate.map { ($0.key, $0.value / 100.0) })
        
        // 👇 应用支付方式加成 (转换百分比)
        card.paymentMethodRates = Dictionary(uniqueKeysWithValues: paymentMethodRates.map { ($0.key, $0.value / 100.0) })

        card.rewardType = rewardType
        card.pointProgram = pointProgram

        card.defaultRate = defaultRate / 100.0
        card.foreignCurrencyRate = foreignCurrencyRate.map { $0 / 100.0 }
        
        card.localBaseCap = localBaseCap
        card.foreignBaseCap = foreignBaseCap
        card.categoryCaps = categoryCaps
        
        // 👇 应用支付方式上限 (直接复制金额，不需要除以100)
        card.paymentCaps = paymentCaps
        
        card.capPeriod = capPeriod
        card.templateKey = templateKey
        if let source = pictureURL {
            
            // CardTemplate.swift 中的 applyRules 可以简化为：
            Task {
                // ✅ 无论 URL 还是 Assets 名字，统统交给 Manager 处理
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

    init(
        templateKey: String,
        bankName: String,
        type: String,
        colors: [String],
        region: Region,
        specialRate: [Category: Double],
        // 新增参数
        paymentMethodRates: [PaymentMethod: Double] = [:],
        rewardType: RewardType = .cashback,
        pointProgram: Point? = nil,
        defaultRate: Double,
        foreignCurrencyRate: Double?,
        localBaseCap: Double = 0,
        foreignBaseCap: Double = 0,
        categoryCaps: [Category: Double] = [:],
        // 新增参数
        paymentCaps: [PaymentMethod: Double] = [:],
        capPeriod: CapPeriod = .yearly,
        pictureURL: String? = nil)
    {
        self.templateKey = templateKey
        self.bankName = bankName
        self.type = type
        self.colors = colors
        self.region = region
        self.specialRate = specialRate
        self.paymentMethodRates = paymentMethodRates // 赋值
        self.rewardType = rewardType
        self.pointProgram = pointProgram
        self.defaultRate = defaultRate
        self.foreignCurrencyRate = foreignCurrencyRate
        self.localBaseCap = localBaseCap
        self.foreignBaseCap = foreignBaseCap
        self.categoryCaps = categoryCaps
        self.paymentCaps = paymentCaps // 赋值
        self.capPeriod = capPeriod
        self.pictureURL = pictureURL
    }
}

// MARK: - Seed data
struct CardTemplateSeed {
    let bankName: String
    let type: String
    let colors: [String]
    let region: Region
    let specialRate: [Category: Double]
    // 👇 新增
    var paymentMethodRates: [PaymentMethod: Double] = [:]

    var rewardType: RewardType = .cashback
    var pointProgram: Point? = nil
    var pointProgramKey: String? = nil

    let defaultRate: Double
    let foreignCurrencyRate: Double?
    var localBaseCap: Double = 0
    var foreignBaseCap: Double = 0
    var categoryCaps: [Category: Double] = [:]
    // 👇 新增
    var paymentCaps: [PaymentMethod: Double] = [:]
    
    var capPeriod: CapPeriod = .yearly

    var templateKey: String { CardTemplate.templateKey(bankName: bankName, type: type) }
    var pictureURL: String? = nil

    func makeModel(pointProgram: Point?) -> CardTemplate {
        CardTemplate(
            templateKey: templateKey,
            bankName: bankName,
            type: type,
            colors: colors,
            region: region,
            specialRate: specialRate,
            paymentMethodRates: paymentMethodRates, // 传参
            rewardType: rewardType,
            pointProgram: pointProgram ?? self.pointProgram,
            defaultRate: defaultRate,
            foreignCurrencyRate: foreignCurrencyRate,
            localBaseCap: localBaseCap,
            foreignBaseCap: foreignBaseCap,
            categoryCaps: categoryCaps,
            paymentCaps: paymentCaps, // 传参
            capPeriod: capPeriod,
            pictureURL: pictureURL
        )
    }

    func apply(to template: CardTemplate, pointProgram: Point?) {
        template.templateKey = templateKey
        template.bankName = bankName
        template.type = type
        template.colors = colors
        template.region = region
        template.specialRate = specialRate
        template.paymentMethodRates = paymentMethodRates // 同步
        template.rewardType = rewardType
        template.pointProgram = pointProgram ?? self.pointProgram
        template.defaultRate = defaultRate
        template.foreignCurrencyRate = foreignCurrencyRate
        template.localBaseCap = localBaseCap
        template.foreignBaseCap = foreignBaseCap
        template.categoryCaps = categoryCaps
        template.paymentCaps = paymentCaps // 同步
        template.capPeriod = capPeriod
        template.pictureURL = pictureURL
    }

    func resolvedPointProgram(from pointMap: [String: Point]) -> Point? {
        if let pointProgramKey {
            return pointMap[pointProgramKey]
        }
        return pointProgram
    }

    static func pointTemplateKey(bankName: String, pointName: String, currencyCode: Region) -> String {
        let parts = [bankName, pointName, currencyCode.currencyCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return parts.joined(separator: "|")
    }
}

extension CardTemplate {
    // 提示：如果你有通过 Apple Pay 返现更高的卡，可以在这里配置
    // 例如: paymentMethodRates: [.applePay: 1.0]
    
    // 若要复用“积分库”里的 Point，可传入 pointProgramKey:
    // pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "HSBC US", pointName: "Point", currencyCode: .us)
    static let defaultSeeds: [CardTemplateSeed] = [
        CardTemplateSeed(bankName: "滙豐香港", type: "Red信用卡", colors: ["DA291C", "005863"], region: .hk, specialRate: [ : ], paymentMethodRates: [.online: 3.0], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "HSBC HK", pointName: "RC", currencyCode: .hk), defaultRate: 1.0, foreignCurrencyRate: 1.0, localBaseCap: 0, foreignBaseCap: 0, categoryCaps: [: ], paymentCaps: [.online: 300],capPeriod: .monthly, pictureURL: "hsbchkred"),
        CardTemplateSeed(bankName: "滙豐香港", type: "Pulse銀聯信用卡 ", colors: ["DB0011", "1A1A1A"], region: .cn, specialRate: [ .dining: 5 ], paymentMethodRates: [.pulse: 2.0], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "HSBC HK", pointName: "RC", currencyCode: .hk), defaultRate: 2.4, foreignCurrencyRate: 2.4, localBaseCap: 2400, foreignBaseCap: 2400, categoryCaps: [.dining: 500], paymentCaps: [.pulse: 1600], capPeriod: .yearly, pictureURL: "hsbchkpulse"),
        CardTemplateSeed(bankName: "滙豐香港", type: "卓越理財信用卡", colors: ["111111", "D9D9D9"], region: .hk, specialRate: [ : ], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "HSBC HK", pointName: "RC", currencyCode: .hk), defaultRate: 0.4, foreignCurrencyRate: 2.4, foreignBaseCap: 2400, capPeriod: .yearly),
        CardTemplateSeed(bankName: "滙豐香港", type: "Visa Signature卡", colors: ["1C1C1C", "757575"], region: .hk, specialRate: [ : ], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "HSBC HK", pointName: "RC", currencyCode: .hk), defaultRate: 1.6, foreignCurrencyRate: 3.6, foreignBaseCap: 3600, capPeriod: .yearly, pictureURL: "hsbcvs"),
        CardTemplateSeed(bankName: "滙豐香港", type: "萬事達卡扣賬卡", colors: ["1D5564", "85BDCD"], region: .hk, specialRate: [ : ], defaultRate: 0.4, foreignCurrencyRate: 0.4, pictureURL: "hsbchkdebit"),
        CardTemplateSeed(bankName: "AMEX HK", type: "Explorer", colors: ["0C1C26", "4B6E7D"], region: .hk, specialRate: [ : ], paymentMethodRates: [.online : 200], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "AMEX HK", pointName: "MR", currencyCode: .hk), defaultRate: 300, foreignCurrencyRate: 1075, pictureURL: "amexhkexplorer"),
        CardTemplateSeed(bankName: "AMEX HK", type: "Blue Cash", colors: ["0C1C26", "4B6E7D"], region: .hk, specialRate: [ : ], defaultRate: 1.2, foreignCurrencyRate: 1.2, pictureURL: "amexhkbluecash"),
        CardTemplateSeed(bankName: "HSBC US", type: "Elite", colors: ["050505", "050505"], region: .us, specialRate: [ .travel: 400,.dining:100], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "HSBC US", pointName: "Point", currencyCode: .us), defaultRate: 100, foreignCurrencyRate: 100, pictureURL: "hsbcuselite"),
        CardTemplateSeed(bankName: "Chase", type: "Sapphire Reserve", colors: ["10213A", "A4B7C6"], region: .us, specialRate: [ .travel: 300, .dining: 200, .other: 700], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "Chase", pointName: "UR", currencyCode: .us), defaultRate: 100, foreignCurrencyRate: 100, pictureURL: "CSR"),
        CardTemplateSeed(bankName: "Chase", type: "Sapphire Preferred", colors: ["0B2E58", "3A75B3"], region: .us, specialRate: [ .travel: 100, .dining: 200, .other: 400, .grocery: 200], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "Chase", pointName: "UR", currencyCode: .us), defaultRate: 110, foreignCurrencyRate: 110, pictureURL: "CSP"),
        CardTemplateSeed(bankName: "Chase", type: "Boundless", colors: ["162130", "31527E"], region: .us, specialRate: [.dining: 300, .other: 400, .grocery: 300], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "Marriott", pointName: "Point", currencyCode: .us), defaultRate: 200, foreignCurrencyRate: 200, categoryCaps: [.grocery : 18000, .dining: 18000],pictureURL: "ChaseBoundless"),

        CardTemplateSeed(bankName: "Chase", type: "Freedom Flex", colors: ["10213A", "A4B7C6"], region: .us, specialRate: [.dining: 200, .other: 400], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "Chase", pointName: "UR", currencyCode: .us), defaultRate: 100, foreignCurrencyRate: 100, pictureURL: "ChaseFreedomFlex"),// change monthly
        CardTemplateSeed(bankName: "Chase", type: "Freedom Unlimited", colors: ["10213A", "A4B7C6"], region: .us, specialRate: [.dining: 150, .other: 250], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "Chase", pointName: "UR", currencyCode: .us), defaultRate: 150, foreignCurrencyRate: 150, pictureURL: "ChaseFreedomUnlimite"),

        CardTemplateSeed(bankName: "AMEX US", type: "Platinum", colors: ["D5D8DA", "54585A"], region: .us, specialRate: [ .travel: 400], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "AMEX US", pointName: "MR", currencyCode: .us), defaultRate: 100, foreignCurrencyRate: 100, pictureURL: "AMEXP"),
        CardTemplateSeed(bankName: "AMEX US", type: "Brilliant", colors: ["001C3D", "00A9E0"], region: .us, specialRate: [ .travel: 100, .dining: 100, .other: 400], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "Marriott", pointName: "Point", currencyCode: .us), defaultRate: 200, foreignCurrencyRate: 200, pictureURL: "amexusbrilliant"),
        CardTemplateSeed(bankName: "AMEX US", type: "Aspire", colors: ["161D3A", "5A97D1"], region: .us, specialRate: [ .travel: 400, .dining: 400, .other: 1100], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "Hilton", pointName: "Point", currencyCode: .us), defaultRate: 300, foreignCurrencyRate: 300, pictureURL: "amexusaspire"),
        CardTemplateSeed(bankName: "HSBC US", type: "Premier", colors: ["24133F", "D92344"], region: .us, specialRate: [ .travel: 100,.grocery:200], rewardType: .points, pointProgramKey: CardTemplateSeed.pointTemplateKey(bankName: "HSBC US", pointName: "Point", currencyCode: .us), defaultRate: 100, foreignCurrencyRate: 100, pictureURL: "hsbcuspremiercard"),
        CardTemplateSeed(bankName: "Ready", type: "Metal", colors: ["BD9850", "F2E9D4"], region: .us, specialRate: [:], defaultRate: 3, foreignCurrencyRate: 3, pictureURL: "ready"),
        CardTemplateSeed(bankName: "Apple", type: "Card", colors: ["F5F5F7", "F8D347"], region: .us, specialRate: [:], paymentMethodRates: [.applePay: 1] , rewardType: .cashback, defaultRate: 1, foreignCurrencyRate: 1, pictureURL: "AppleCard"),
        CardTemplateSeed(bankName: "工銀亞洲", type: "Visa Signature", colors: ["121212", "EDC457"], region: .hk, specialRate: [ : ], defaultRate: 1.5, foreignCurrencyRate: 1.5, categoryCaps: [: ], pictureURL: "icbcasiavs"),
        CardTemplateSeed(bankName: "工銀亞洲", type: "粵港澳灣區信用卡", colors: ["0F0F0F", "C0C0C0"], region: .cn, specialRate: [ : ], paymentMethodRates: [.qrCode : 5, .offline : 5], defaultRate: 1.5, foreignCurrencyRate: 1.5, categoryCaps: [: ], paymentCaps: [.qrCode: 200, .offline : 200], capPeriod: .monthly, pictureURL: "icbcasiagba"),
        CardTemplateSeed(bankName: "信銀國際", type: "大灣區雙幣信用卡", colors: ["8A8F99", "E3DEE9"], region: .cn, specialRate: [ : ], paymentMethodRates: [.gba : 6], defaultRate: 4, foreignCurrencyRate: 0.4, localBaseCap: 150, foreignBaseCap: 0, categoryCaps: [: ], paymentCaps: [.gba: 250], capPeriod: .monthly),
        CardTemplateSeed(bankName: "中銀香港", type: "萬事達卡扣賬卡", colors: ["121212", "D4B979"], region: .hk, specialRate: [ : ], defaultRate: 0.5, foreignCurrencyRate: 0.5, pictureURL: "bocdebit"),
        CardTemplateSeed(bankName: "农业银行", type: "大学生青春卡", colors: ["9EC0B3", "D9A62E"], region: .cn, specialRate: [ : ], paymentMethodRates: [.applePay : 1], defaultRate: 0.1, foreignCurrencyRate: 3, foreignBaseCap: 100, paymentCaps: [.applePay : 200], capPeriod: .monthly),
        CardTemplateSeed(bankName: "农业银行", type: "Visa尊然白金信用卡", colors: ["1A1A1A", "C4C6C8"], region: .cn, specialRate: [ : ], defaultRate: 0.1, foreignCurrencyRate: 3, foreignBaseCap: 70,capPeriod: .monthly, pictureURL: "abcvisa"),
        CardTemplateSeed(bankName: "工商银行", type: "牡丹祥运信用卡", colors: ["2F2F2F", "C7A04D"], region: .cn, specialRate: [ : ], defaultRate: 0, foreignCurrencyRate: 3, pictureURL: "icbcsafari"),
        
    ]

    static func syncDefaultTemplates(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<CardTemplate>()
        let currentTemplates = try context.fetch(descriptor)
        let currentMap = Dictionary(uniqueKeysWithValues: currentTemplates.map { ($0.templateKey, $0) })

        let pointDescriptor = FetchDescriptor<Point>()
        let currentPoints = try context.fetch(pointDescriptor)
        let pointMap = Dictionary(uniqueKeysWithValues: currentPoints.map {
            (CardTemplateSeed.pointTemplateKey(bankName: $0.bankName, pointName: $0.pointName, currencyCode: $0.valueCurrencyCode), $0)
        })

        for seed in defaultSeeds {
            let resolvedPointProgram = seed.resolvedPointProgram(from: pointMap)
            if let existing = currentMap[seed.templateKey] {
                seed.apply(to: existing, pointProgram: resolvedPointProgram)
            } else {
                context.insert(seed.makeModel(pointProgram: resolvedPointProgram))
            }
        }
    }

    static func refreshCardsFromTemplates(in context: ModelContext) throws {
        let templates = try context.fetch(FetchDescriptor<CardTemplate>())
        let templateMap = Dictionary(uniqueKeysWithValues: templates.map { ($0.templateKey, $0) })
        let cards = try context.fetch(FetchDescriptor<CreditCard>())

        for card in cards {
            guard let key = card.templateKey, let template = templateMap[key] else { continue }
            template.applyRules(to: card)
        }
    }
}
