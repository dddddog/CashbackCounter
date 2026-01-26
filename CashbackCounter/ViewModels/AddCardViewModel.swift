//
//  AddCardViewModel.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 1/26/26.
//

import Foundation
import SwiftUI
import SwiftData

@Observable
class AddCardViewModel {
    // --- 状态变量 ---
    var bankName: String = ""
    var cardType: String = ""
    var endNum: String = ""
    var repaymentDayStr: String = ""
    
    var color1: Color = .blue
    var color2: Color = .purple
    var region: Region = .cn
    var capPeriod: CapPeriod = .monthly
    
    // 费率字符串
    var defaultRateStr: String = "1.0"
    var foreignRateStr: String = ""
    var diningRateStr: String = ""
    var groceryRateStr: String = ""
    var travelRateStr: String = ""
    var digitalRateStr: String = ""
    var otherRateStr: String = ""
    
    // 上限字符串
    var localBaseCapStr: String = ""
    var foreignBaseCapStr: String = ""
    var diningCapStr: String = ""
    var groceryCapStr: String = ""
    var travelCapStr: String = ""
    var digitalCapStr: String = ""
    var otherCapStr: String = ""
    
    // 内部引用
    private let repository: TransactionRepositoryProtocol // ✨ 注入协议
    private var cardToEdit: CreditCard?
    private var template: CardTemplate?

    // --- 初始化：处理三种模式 (编辑/模板/新建) ---
    init(repository: TransactionRepositoryProtocol, cardToEdit: CreditCard? = nil, template: CardTemplate? = nil) {
        self.cardToEdit = cardToEdit
        self.template = template
        self.repository = repository
        
        if let card = cardToEdit {
            setupFromCard(card)
        } else if let template = template {
            setupFromTemplate(template)
        }
    }

    // 从现有卡片回填数据
    private func setupFromCard(_ card: CreditCard) {
        bankName = card.bankName
        cardType = card.type
        endNum = card.endNum
        repaymentDayStr = card.repaymentDay > 0 ? String(card.repaymentDay) : ""
        region = card.issueRegion
        capPeriod = card.capPeriod
        
        if card.colors.count >= 2 {
            color1 = card.colors[0]
            color2 = card.colors[1]
        }
        
        defaultRateStr = formatRate(card.defaultRate)
        foreignRateStr = card.foreignCurrencyRate != nil ? formatRate(card.foreignCurrencyRate!) : ""
        
        // 特殊费率回填
        diningRateStr = formatRate(card.specialRates[.dining])
        groceryRateStr = formatRate(card.specialRates[.grocery])
        travelRateStr = formatRate(card.specialRates[.travel])
        digitalRateStr = formatRate(card.specialRates[.digital])
        otherRateStr = formatRate(card.specialRates[.other])
        
        // 上限回填
        localBaseCapStr = formatCap(card.localBaseCap)
        foreignBaseCapStr = formatCap(card.foreignBaseCap)
        diningCapStr = formatCap(card.categoryCaps[.dining])
        groceryCapStr = formatCap(card.categoryCaps[.grocery])
        travelCapStr = formatCap(card.categoryCaps[.travel])
        digitalCapStr = formatCap(card.categoryCaps[.digital])
        otherCapStr = formatCap(card.categoryCaps[.other])
    }

    // 从模板初始化数据
    private func setupFromTemplate(_ template: CardTemplate) {
        bankName = template.bankName
        cardType = template.type
        endNum = "8888"
        region = template.region
        capPeriod = template.capPeriod
        
        if template.colors.count >= 2 {
            color1 = Color(hex: template.colors[0])
            color2 = Color(hex: template.colors[1])
        }
        
        defaultRateStr = String(format: "%.1f", template.defaultRate).replacingOccurrences(of: ".0", with: "")
        foreignRateStr = template.foreignCurrencyRate != nil ? String(format: "%.1f", template.foreignCurrencyRate!).replacingOccurrences(of: ".0", with: "") : ""
        
        diningRateStr = formatRateFromTemplate(template.specialRate[.dining])
        groceryRateStr = formatRateFromTemplate(template.specialRate[.grocery])
        travelRateStr = formatRateFromTemplate(template.specialRate[.travel])
        digitalRateStr = formatRateFromTemplate(template.specialRate[.digital])
        otherRateStr = formatRateFromTemplate(template.specialRate[.other])
        
        localBaseCapStr = formatCap(template.localBaseCap)
        foreignBaseCapStr = formatCap(template.foreignBaseCap)
        diningCapStr = formatCap(template.categoryCaps[.dining])
        groceryCapStr = formatCap(template.categoryCaps[.grocery])
        travelCapStr = formatCap(template.categoryCaps[.travel])
        digitalCapStr = formatCap(template.categoryCaps[.digital])
        otherCapStr = formatCap(template.categoryCaps[.other])
    }

    // --- 保存逻辑 ---
    func save() -> Bool {
        let defRate = (Double(defaultRateStr) ?? 0) / 100.0
        let rDay = Int(repaymentDayStr) ?? 0
        let foreignRate = foreignRateStr.isEmpty ? nil : (Double(foreignRateStr) ?? 0) / 100.0
        let c1Hex = color1.toHex() ?? "0000FF"
        let c2Hex = color2.toHex() ?? "000000"
        
        // 处理字典数据
        let specialRates = getSpecialRatesDict()
        let catCaps = getCategoryCapsDict()
        let locBaseCap = Double(localBaseCapStr) ?? 0
        let forBaseCap = Double(foreignBaseCapStr) ?? 0

        if let existingCard = cardToEdit {
            // 更新模式
            existingCard.bankName = bankName
            existingCard.type = cardType
            existingCard.endNum = endNum
            existingCard.colorHexes = [c1Hex, c2Hex]
            existingCard.defaultRate = defRate
            existingCard.issueRegion = region
            existingCard.foreignCurrencyRate = foreignRate
            existingCard.capPeriod = capPeriod
            existingCard.specialRates = specialRates
            existingCard.localBaseCap = locBaseCap
            existingCard.foreignBaseCap = forBaseCap
            existingCard.categoryCaps = catCaps
            existingCard.repaymentDay = rDay
            NotificationManager.shared.scheduleNotification(for: existingCard)
        } else {
            // 新建模式
            let newCard = CreditCard(
                bankName: bankName, type: cardType, endNum: endNum,
                colorHexes: [c1Hex, c2Hex], defaultRate: defRate,
                specialRates: specialRates, issueRegion: region,
                foreignCurrencyRate: foreignRate, templateKey: template?.templateKey,
                localBaseCap: locBaseCap, foreignBaseCap: forBaseCap,
                categoryCaps: catCaps, capPeriod: capPeriod, repaymentDay: rDay
            )
            repository.insertCard(newCard) // ✅ 使用 repository
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationManager.shared.scheduleNotification(for: newCard)
            }
        }
                
        // 统一保存
        do {
            try repository.save() // ✅ 统一保存入口
            return true
        } catch {
            print("卡片保存失败: \(error)")
            return false
        }
    }

    // --- 辅助方法 ---
    private func formatRate(_ rate: Double?) -> String {
        guard let r = rate, r > 0 else { return "" }
        return String(r * 100)
    }
    
    private func formatRateFromTemplate(_ rate: Double?) -> String {
        guard let r = rate else { return "" }
        return String(format: "%.1f", r).replacingOccurrences(of: ".0", with: "")
    }

    private func formatCap(_ cap: Double?) -> String {
        guard let c = cap, c > 0 else { return "" }
        return String(format: "%.0f", c)
    }

    private func getSpecialRatesDict() -> [Category: Double] {
        var dict: [Category: Double] = [:]
        if let r = Double(diningRateStr), r > 0 { dict[.dining] = r / 100.0 }
        if let r = Double(groceryRateStr), r > 0 { dict[.grocery] = r / 100.0 }
        if let r = Double(travelRateStr), r > 0 { dict[.travel] = r / 100.0 }
        if let r = Double(digitalRateStr), r > 0 { dict[.digital] = r / 100.0 }
        if let r = Double(otherRateStr), r > 0 { dict[.other] = r / 100.0 }
        return dict
    }

    private func getCategoryCapsDict() -> [Category: Double] {
        var dict: [Category: Double] = [:]
        if let c = Double(diningCapStr), c > 0 { dict[.dining] = c }
        if let c = Double(groceryCapStr), c > 0 { dict[.grocery] = c }
        if let c = Double(travelCapStr), c > 0 { dict[.travel] = c }
        if let c = Double(digitalCapStr), c > 0 { dict[.digital] = c }
        if let c = Double(otherCapStr), c > 0 { dict[.other] = c }
        return dict
    }
}
