// TrendAnalysisViewModel.swift
import SwiftUI
import SwiftData

@Observable
class TrendAnalysisViewModel {
    // --- 1. UI 状态 ---
    var selectedTimeframe: Timeframe = .oneMonth
    
    // --- 2. 内部数据 ---
    private var transactions: [Transaction] = []
    private var exchangeRates: [String: Double] = [:]
    var type: TrendType = .expense
    
    enum Timeframe: String, CaseIterable {
        case sevenDays = "7天", oneMonth = "1月", sixMonths = "6月", oneYear = "1年", all = "全部"
    }
    
    enum TrendType {
        case expense, cashback
    }
    
    struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
    }

    // --- 3. 初始化 ---
    init(transactions: [Transaction], exchangeRates: [String: Double], type: TrendType) {
        self.transactions = transactions
        self.exchangeRates = exchangeRates
        self.type = type
    }

    // --- 4. 核心逻辑：生成图表数据 ---
    var chartData: [ChartPoint] {
        let filtered = filterTransactionsByTimeframe()
        let grouped = groupTransactions(filtered)
        
        return grouped.map { date, amount in
            ChartPoint(date: date, amount: amount)
        }.sorted { $0.date < $1.date }
    }

    private func filterTransactionsByTimeframe() -> [Transaction] {
        let now = Date()
        let calendar = Calendar.current
        
        return transactions.filter { t in
            switch selectedTimeframe {
            case .sevenDays:
                return t.date >= calendar.date(byAdding: .day, value: -7, to: now)!
            case .oneMonth:
                return t.date >= calendar.date(byAdding: .month, value: -1, to: now)!
            case .sixMonths:
                return t.date >= calendar.date(byAdding: .month, value: -6, to: now)!
            case .oneYear:
                return t.date >= calendar.date(byAdding: .year, value: -1, to: now)!
            case .all:
                return true
            }
        }
    }

    private func groupTransactions(_ list: [Transaction]) -> [Date: Double] {
        var dict: [Date: Double] = [:]
        let calendar = Calendar.current
        
        for t in list {
            // 根据时间范围决定分组粒度
            let components: Set<Calendar.Component> = (selectedTimeframe == .sixMonths || selectedTimeframe == .oneYear || selectedTimeframe == .all)
                ? [.year, .month]
                : [.year, .month, .day]
            
            let dateKey = calendar.date(from: calendar.dateComponents(components, from: t.date))!
            
            // 计算转换后的金额
            let code = t.card?.issueRegion.currencyCode ?? "CNY"
            let rate = exchangeRates[code] ?? 1.0
            let amount = (type == .expense ? t.billingAmount : CashbackService.calculateCashback(for: t)) / rate
            
            dict[dateKey, default: 0] += amount
        }
        return dict
    }
    
    // 统计总额
    var totalAmount: Double {
        chartData.reduce(0) { $0 + $1.amount }
    }
}
