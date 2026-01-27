//
//  CashbackService.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/23/25.
//

import Foundation

struct CashbackService {
    
    static func calculateCashback(for transaction: Transaction) -> Double {
            // 这里的 cashbackamount 是我们在 AddTransactionView 保存时
            // 调用 card.calculateCappedCashback 算出来的结果，已经包含上限逻辑
            return transaction.cashbackamount
        }
    
    // 获取卡名
    static func getCardName(for transaction: Transaction) -> String {
        guard let card = transaction.card else { return "已删除卡片" }
        return "\(card.bankName) \(card.type)"
    }
    // 获取卡号
    static func getCardNum(for transaction: Transaction) -> String {
        guard let card = transaction.card else { return "已删除卡片" }
        return "\(card.endNum)"
    }
    // 获取货币符号
    static func getCurrency(for transaction: Transaction) -> String {
        return transaction.location.currencySymbol
    }
    
    // 获取费率
    static func getRate(for transaction: Transaction) -> Double {
        guard let card = transaction.card else { return 0.0 }
        return card.getRate(for: transaction.category, location: transaction.location, payment: transaction.paymentMethod)
    }
    
}

// Convert string to date
extension String {
    func toDate() -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd" // 必须符合这个格式
        return formatter.date(from: self) ?? Date() // 如果格式错了就返回今天
    }
}
