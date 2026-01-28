//
//  CSVHelper.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/25/25.
//

import Foundation
import SwiftUI
import SwiftData
import ZIPFoundation

struct CSVHelper {
    
    // MARK: - Receipt filename helpers
    private static let receiptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
    
    private static func sanitizedMerchantComponent(_ merchant: String) -> String {
        let sanitized = merchant
            .replacingOccurrences(of: "[^A-Za-z0-9_\\u4e00-\\u9fa5-]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        
        let truncated = String(sanitized.prefix(40))
        return truncated.isEmpty ? "receipt" : truncated
    }
    
    fileprivate static func receiptFilename(for merchant: String, date: Date, index: Int) -> String {
        let dateString = receiptDateFormatter.string(from: date)
        let merchantComponent = sanitizedMerchantComponent(merchant)
        return "receipt_\(dateString)_\(merchantComponent)_\(index).jpg"
    }
    
    // MARK: - 导入交易逻辑
    static func importBackupZip(url: URL, context: ModelContext, allCards: [CreditCard]) throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }
        
        // 1. 解压
        try fileManager.unzipItem(at: url, to: tempDir)
        
        // 2. 寻找 CSV
        let csvURL = tempDir.appendingPathComponent("Transactions.csv")
        guard fileManager.fileExists(atPath: csvURL.path) else {
            throw NSError(domain: "CSVHelper", code: 404, userInfo: [NSLocalizedDescriptionKey: "ZIP 文件中未找到 Transactions.csv"])
        }
        
        // 3. 读取内容
        let content = try String(contentsOf: csvURL, encoding: .utf8)
        // 3. 预处理图片映射 (核心修改) 👇
        let receiptsDir = tempDir.appendingPathComponent("Receipts")
        var receiptMap: [Int: URL] = [:]
                
        if fileManager.fileExists(atPath: receiptsDir.path) {
            receiptMap = try buildReceiptIndexMap(in: receiptsDir)
            print("已建立图片索引映射，共找到 \(receiptMap.count) 张图片")
        }
        
        // 5. 解析交易
        let createdTransactions = try parseTransactionCSV(content: content, context: context, allCards: allCards, receiptMap: receiptMap)
        
        // 6. 解析收入
        let incomeURL = tempDir.appendingPathComponent("Income.csv")
        if fileManager.fileExists(atPath: incomeURL.path) {
            let incomeContent = try String(contentsOf: incomeURL, encoding: .utf8)
            parseIncomeCSV(content: incomeContent, context: context, transactions: createdTransactions)
        }
    }

    // MARK: - 导入 CSV 核心逻辑 (已更新支持 PaymentMethod)
    static func parseTransactionCSV(content: String, context: ModelContext, allCards: [CreditCard], receiptMap: [Int: URL]? = nil) throws -> [Transaction] {
        let rows = content.components(separatedBy: .newlines)
        var createdTransactions: [Transaction] = []
        
        let categoryMap: [String: Category] = Dictionary(uniqueKeysWithValues: Category.allCases.map { ($0.displayName, $0) })
        let regionMap: [String: Region] = Dictionary(uniqueKeysWithValues: Region.allCases.map { ($0.rawValue, $0) })
        var logicalIndex = 0
        for (index, row) in rows.enumerated() {
            if index == 0 || row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            
            let columns = splitCSVLine(row)
            if columns.count < 9 { continue }
            logicalIndex += 1
            // 1. 解析基础字段
            let dateStr = columns[0]
            let merchant = cleanCSVField(columns[1])
            let categoryName = columns[2]
            let amount = Double(columns[3]) ?? 0.0
            let billing = Double(columns[4]) ?? 0.0
            let cashback = Double(columns[5]) ?? 0.0
            let cardNameRaw = cleanCSVField(columns[6])
            let cardEndNum = columns[7]
            let regionName = columns[8]
            
            // 👇 新增：解析支付方式 (第10列，索引9)
            // 兼容旧版 CSV：如果列数不够，或者读出来是空的，就默认 .offline
            var paymentMethod: PaymentMethod = .offline
            if columns.count > 9 {
                let methodRaw = cleanCSVField(columns[9]).trimmingCharacters(in: .whitespacesAndNewlines)
                // 尝试用 rawValue 匹配 (例如 "applePay")
                if let method = PaymentMethod(rawValue: methodRaw) {
                    paymentMethod = method
                }
            }
            
            let date = dateStr.toDate()
            let category = categoryMap[categoryName] ?? .other
            let cleanRegionName = regionName.trimmingCharacters(in: .whitespacesAndNewlines)
            let region = regionMap[cleanRegionName] ?? .cn
            
            // 2. 尝试匹配收据图片
            var receiptData: Data? = nil
            if let fileURL = receiptMap?[logicalIndex] {
                do {
                    receiptData = try Data(contentsOf: fileURL)
                    // print("成功匹配图片: ID \(logicalIndex) -> \(fileURL.lastPathComponent)")
                } catch {
                    print("图片读取失败: \(fileURL.path)")
                }
            }
            
            // 3. 匹配卡片
            var matchedCard: CreditCard? = nil
            if cardEndNum != "无卡" && cardNameRaw != "已删除卡片" {
                matchedCard = allCards.first { card in
                    let dbCardName = "\(card.bankName) \(card.type)"
                    return card.endNum == cardEndNum && dbCardName == cardNameRaw
                }
                if matchedCard == nil {
                    matchedCard = allCards.first { $0.endNum == cardEndNum }
                }
            }
            
            // 4. 创建交易 (传入 paymentMethod)
            let newTransaction = Transaction(
                merchant: merchant,
                category: category,
                location: region,
                amount: amount,
                date: date,
                card: matchedCard,
                receiptData: receiptData,
                billingAmount: billing,
                cashbackAmount: cashback,
                paymentMethod: paymentMethod // 👈 写入数据库
            )
            
            context.insert(newTransaction)
            createdTransactions.append(newTransaction)
        }
        return createdTransactions
    }
    private static func buildReceiptIndexMap(in directory: URL) throws -> [Int: URL] {
            let fileManager = FileManager.default
            let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            
            var map: [Int: URL] = [:]
            
            for url in fileURLs {
                let filename = url.deletingPathExtension().lastPathComponent // 去掉 .jpg
                // 文件名格式: receipt_20251205_Merchant_92
                // 我们只需要最后一个 "_" 后面的数字
                
                let components = filename.components(separatedBy: "_")
                if let lastComponent = components.last, let index = Int(lastComponent) {
                    map[index] = url
                }
            }
            return map
        }
    
    private static func parseIncomeCSV(content: String, context: ModelContext, transactions: [Transaction]) {
        let rows = content.components(separatedBy: .newlines)
        let regionMap: [String: Region] = Dictionary(uniqueKeysWithValues: Region.allCases.map { ($0.rawValue, $0) })
        
        for (index, row) in rows.enumerated() {
            if index == 0 || row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let columns = splitCSVLine(row)
            if columns.count < 11 { continue }
            
            let dateStr = columns[0]
            let amount = Double(columns[1]) ?? 0.0
            let regionRaw = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = cleanCSVField(columns[3])
            let platform = cleanCSVField(columns[4])
            let isReceived = (columns[5].trimmingCharacters(in: .whitespacesAndNewlines) == "1")
            let transactionIndex = Int(columns[6])
            let txMerchant = cleanCSVField(columns[7])
            let txDateStr = columns[8]
            let txAmount = Double(columns[9]) ?? 0.0
            let txRegionRaw = columns[10].trimmingCharacters(in: .whitespacesAndNewlines)
            
            let date = dateStr.toDate()
            let region = regionMap[regionRaw] ?? .cn
            
            var matchedTransaction: Transaction? = nil
            if let idx = transactionIndex, idx > 0, idx <= transactions.count {
                matchedTransaction = transactions[idx - 1]
            } else {
                matchedTransaction = transactions.first(where: { t in
                    t.merchant == txMerchant &&
                    t.dateString == txDateStr &&
                    abs(t.amount - txAmount) < 0.0001 &&
                    t.location.rawValue == txRegionRaw
                })
            }
            
            let income = Income(
                amount: amount,
                date: date,
                location: region,
                transaction: matchedTransaction,
                detail: detail,
                platform: platform,
                isReceived: isReceived
            )
            context.insert(income)
        }
    }
    
    // 🛠 辅助方法
    private static func cleanCSVField(_ text: String) -> String {
        var s = text
        if s.hasPrefix("\"") && s.hasSuffix("\"") {
            s.removeFirst()
            s.removeLast()
        }
        return s.replacingOccurrences(of: "\"\"", with: "\"")
    }
    
    private static func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
                current.append(char)
            } else if char == "," && !insideQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }
}

// MARK: - Export Extension (已更新支持 PaymentMethod)
extension Array where Element == Transaction {
    
    func generateCSV() -> String {
        // 👇 修改表头：末尾增加 "支付方式"
        var csvString = "交易时间,商户名称,消费类别,消费金额(原币),入账金额(本币),返现金额(本币),支付卡片,卡片尾号,消费地区,支付方式\n"
        
        for t in self {
            let date = t.dateString
            let safeMerchant = t.merchant.replacingOccurrences(of: "\"", with: "\"\"")
            let merchant = "\"\(safeMerchant)\""
            
            let category = t.category.displayName
            let amount = String(format: "%.2f", t.amount)
            let billing = String(format: "%.2f", t.billingAmount)
            let cashback = String(format: "%.2f", t.cashbackamount)
            let cardNumber = t.card?.endNum ?? "无卡"
            let cardName = t.card != nil ? "\"\(t.card!.bankName) \(t.card!.type)\"" : "已删除卡片"
            let region = t.location.rawValue
            
            // 👇 新增：获取支付方式的 rawValue (如 "applePay")
            let paymentMethod = t.paymentMethod.rawValue
            
            // 👇 拼接到最后
            let row = "\(date),\(merchant),\(category),\(amount),\(billing),\(cashback),\(cardName),\(cardNumber),\(region),\(paymentMethod)\n"
            csvString.append(row)
        }
        return csvString
    }
    
    func exportReceiptsZip() -> URL? {
        let fileManager = FileManager.default
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = timestampFormatter.string(from: Date())
        
        let rootFolderName = "Cashback_Export_\(timestamp)"
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(rootFolderName)
        let zipURL = fileManager.temporaryDirectory.appendingPathComponent("\(rootFolderName).zip")
        
        do {
            if fileManager.fileExists(atPath: rootURL.path) {
                try fileManager.removeItem(at: rootURL)
            }
            if fileManager.fileExists(atPath: zipURL.path) {
                try fileManager.removeItem(at: zipURL)
            }
            
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            
            let bom = "\u{FEFF}"
            let csvString = bom + self.generateCSV()
            let csvURL = rootURL.appendingPathComponent("Transactions.csv")
            try csvString.write(to: csvURL, atomically: true, encoding: .utf8)
            
            var incomeRows: [String] = []
            let incomeHeader = "收入日期,收入金额,收入地区,交易内容,交易平台,是否收款,交易索引,关联商户,关联交易日期,关联交易金额,关联交易地区\n"
            incomeRows.append(incomeHeader)
            
            let receiptsDir = rootURL.appendingPathComponent("Receipts")
            try fileManager.createDirectory(at: receiptsDir, withIntermediateDirectories: true)
            
            for (index, transaction) in self.enumerated() {
                if let data = transaction.receiptData {
                    let filename = CSVHelper.receiptFilename(
                        for: transaction.merchant,
                        date: transaction.date,
                        index: index + 1
                    )
                    let fileURL = receiptsDir.appendingPathComponent(filename)
                    try? data.write(to: fileURL)
                }
                
                if let incomes = transaction.incomes {
                    for income in incomes {
                        let row = Self.incomeCSVRow(for: income, transaction: transaction, transactionIndex: index + 1)
                        incomeRows.append(row)
                    }
                }
            }
            
            let incomeContent = "\u{FEFF}" + incomeRows.joined()
            let incomeURL = rootURL.appendingPathComponent("Income.csv")
            try incomeContent.write(to: incomeURL, atomically: true, encoding: .utf8)
            
            try fileManager.zipItem(at: rootURL, to: zipURL, shouldKeepParent: false)
            try? fileManager.removeItem(at: rootURL)
            
            return zipURL
            
        } catch {
            print("打包导出失败: \(error)")
            return nil
        }
    }
    
    private static func incomeCSVRow(for income: Income, transaction: Transaction, transactionIndex: Int) -> String {
        let incomeDate = income.dateString
        let incomeAmount = String(format: "%.2f", income.amount)
        let incomeRegion = income.location.rawValue
        let detail = "\"\(income.detail.replacingOccurrences(of: "\"", with: "\"\""))\""
        let platform = "\"\(income.platform.replacingOccurrences(of: "\"", with: "\"\""))\""
        let receivedFlag = income.isReceived ? "1" : "0"
        
        let txMerchant = "\"\(transaction.merchant.replacingOccurrences(of: "\"", with: "\"\""))\""
        let txDate = transaction.dateString
        let txAmount = String(format: "%.2f", transaction.amount)
        let txRegion = transaction.location.rawValue
        
        return "\(incomeDate),\(incomeAmount),\(incomeRegion),\(detail),\(platform),\(receivedFlag),\(transactionIndex),\(txMerchant),\(txDate),\(txAmount),\(txRegion)\n"
    }
}
