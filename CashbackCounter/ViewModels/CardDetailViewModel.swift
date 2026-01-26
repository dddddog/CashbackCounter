// CardDetailViewModel.swift
import SwiftUI
import SwiftData

@Observable
class CardDetailViewModel {
    // --- 1. 数据模型 ---
    let card: CreditCard
    
    // --- 2. 初始化 ---
    init(card: CreditCard) {
        self.card = card
    }
    
    // --- 3. 业务逻辑：排序后的交易列表 ---
    // 将排序逻辑从 View 移到这里
    var sortedTransactions: [Transaction] {
        (card.transactions ?? []).sorted { $0.date > $1.date }
    }
    
    // --- 4. 未来扩展点：可以在这里增加统计逻辑 ---
    /*
    var monthlySpending: Double {
        // 计算该卡本月总支出
        // ...
    }
    
    var cashbackProgress: Double {
        // 计算返现额度使用进度
        // ...
    }
    */
}
