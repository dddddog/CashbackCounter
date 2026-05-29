//
//  AddTransactionFromScreenshotIntent.swift
//  CashbackCounter
//
//  通过快捷指令传入截屏图片，OCR 识别后自动创建交易
//

import AppIntents
import SwiftUI
import UIKit
import SwiftData
import UniformTypeIdentifiers

/// 通过屏幕截图添加交易的意图（配合操作按钮 + 快捷指令使用）
struct AddTransactionFromScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "从屏幕截图添加交易"
    static var description = IntentDescription("截取屏幕内容，OCR 识别后自动记账")

    // 参数：快捷指令传入的截图文件
    @Parameter(
        title: "屏幕截图",
        description: "快捷指令截取的屏幕截图",
        supportedContentTypes: [.image]
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("识别截图 \(\.$screenshot) 并记账")
    }

    private static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Transaction.self, CreditCard.self, Point.self)
        } catch {
            fatalError("Failed to create shared model container: \(error)")
        }
    }()

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let modelContext = ModelContext(Self.sharedModelContainer)

        // 1. IntentFile → UIImage
        let imageData = screenshot.data
        guard let image = UIImage(data: imageData) else {
            throw NSError(
                domain: "AddTransactionFromScreenshotIntent",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "无法读取截图数据"]
            )
        }

        // 2. OCR 文字提取（Vision）
        let broadLanguages = ["zh-Hans", "en-US", "ja-JP", "zh-Hant"]
        let rawText = await OCRService.recognizeTextInRows(from: image, languages: broadLanguages)

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "AddTransactionFromScreenshotIntent",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "截图中未识别到文字内容"]
            )
        }

        // 3. AI 解析（独立 ReceiptParser，使用 try await 暴露错误）
        let parser = ReceiptParser()
        let metadata = try await parser.parse(text: rawText)

        // 4. 核心字段检查
        guard let merchant = metadata.merchant,
              let amount = metadata.totalAmount else {
            throw NSError(
                domain: "AddTransactionFromScreenshotIntent",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "未能从截图中识别出商户名或金额"]
            )
        }

        let category = metadata.category ?? .other

        // 使用 OCR 解析出的日期，解析失败则回退到当前日期
        let date: Date = {
            guard let dateStr = metadata.dateString else { return Date() }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.date(from: dateStr) ?? Date()
        }()

        // 5. 根据 currency 推断 Region
        let region: Region
        switch metadata.currency {
        case let code where code?.contains("CNY") == true: region = .cn
        case let code where code?.contains("USD") == true: region = .us
        case let code where code?.contains("HKD") == true: region = .hk
        case let code where code?.contains("JPY") == true: region = .jp
        case let code where code?.contains("NZD") == true: region = .nz
        case let code where code?.contains("TWD") == true: region = .tw
        case let code where code?.contains("GBP") == true: region = .uk
        case let code where code?.contains("MOP") == true: region = .mo
        default:                                            region = .cn
        }

        // 6. 尝试匹配信用卡
        let availableCards = try modelContext.fetch(FetchDescriptor<CreditCard>())
        let selectedCard: CreditCard? = {
            if let last4 = metadata.cardLast4 {
                if let matched = availableCards.first(where: { $0.endNum == last4 }) {
                    return matched
                }
            }
            
            // 尝试使用默认卡片
            let defaultCardID = UserDefaults.standard.string(forKey: "defaultCardID") ?? ""
            if !defaultCardID.isEmpty {
                let parts = defaultCardID.split(separator: "|")
                if parts.count == 2 {
                    let bank = String(parts[0])
                    let end = String(parts[1])
                    return availableCards.first { $0.bankName == bank && $0.endNum == end }
                }
            }
            return nil
        }()

        // 7. 计算入账金额和返现
        let billingAmount = amount
        var cashback: Double = 0.0
        var pointsEarned: Int = 0

        if let card = selectedCard {
            if card.rewardType == .points {
                let pointValue = await resolvePointValueInCardCurrency(
                    pointProgram: card.pointProgram,
                    cardCurrency: card.issueRegion.currencyCode
                )
                let result = card.calculateCappedPoints(
                    amount: billingAmount,
                    category: category,
                    location: region,
                    date: date,
                    paymentMethod: .offline,
                    pointValueInCardCurrency: pointValue
                )
                cashback = result.value
                pointsEarned = result.points
            } else {
                cashback = card.calculateCappedCashback(
                    amount: billingAmount,
                    category: category,
                    location: region,
                    date: date,
                    paymentMethod: .offline
                )
            }
        }

        // 8. 请求用户确认
        let currencySymbol = region.currencySymbol
        let cardName = selectedCard != nil ? "\(selectedCard!.bankName)尾号\(selectedCard!.endNum)" : "默认分类"
        let confirmDialog = IntentDialog("识别出：\(merchant) \(currencySymbol)\(String(format: "%.2f", amount))\n将记入 \(cardName)，是否确认？")
        try await requestConfirmation(result: .result(dialog: confirmDialog))

        // 9. 创建并保存交易（附带截图作为收据）
        let receiptData = image.jpegData(compressionQuality: 0.5)
        let newTransaction = Transaction(
            merchant: merchant,
            category: category,
            location: region,
            amount: amount,
            date: date,
            card: selectedCard,
            receiptData: receiptData,
            billingAmount: billingAmount,
            cashbackAmount: cashback,
            pointsEarned: pointsEarned
        )
        modelContext.insert(newTransaction)
        try modelContext.save()

        // 10. 返回结果
        return .result(dialog: "✅ 已添加：\(merchant) – \(currencySymbol)\(String(format: "%.2f", amount))")
    }

    private func resolvePointValueInCardCurrency(pointProgram: Point?, cardCurrency: String) async -> Double {
        guard let pointProgram else { return 0 }
        let pointRegion = pointProgram.valueCurrencyCode
        if pointRegion.currencyCode == cardCurrency {
            return pointProgram.pointValue
        }
        let rates = await CurrencyService.getRates(base: pointRegion.currencyCode)
        if let rate = rates[cardCurrency], rate > 0 {
            return pointProgram.pointValue * rate
        }
        return pointProgram.pointValue
    }
}
