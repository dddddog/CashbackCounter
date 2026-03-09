import SwiftUI
import Charts
import SwiftData

// 1. 定义分析类型：支出 vs 返现
enum TrendType {
    case expense  // 支出
    case cashback // 返现
    
    var title: String {
        switch self {
        case .expense : return "支出"
        case .cashback: return "返现"
        }
    }
    
    var color: Color {
        switch self {
        case .expense: return .red   // 支出用红色
        case .cashback: return .green // 返现用绿色
        }
    }
}

// 数据点结构
struct MonthlyData: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
}

struct TrendAnalysisView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("mainCurrencyCode") private var mainCurrencyCode: String = "CNY"
    
    // 外部传入的数据
    var transactions: [Transaction]
    var cards: [CreditCard]
    var exchangeRates: [String: Double]
    
    // 👇 核心：当前分析的类型 (由外部传入)
    let type: TrendType
    
    @State private var selectedCard: CreditCard? = nil

    private func exchangeRate(for currencyCode: String) -> Double {
        if currencyCode == mainCurrencyCode { return 1.0 }
        if let rate = exchangeRates[currencyCode] { return rate }
        if let rate = exchangeRates[currencyCode.uppercased()] { return rate }
        if let rate = exchangeRates[currencyCode.lowercased()] { return rate }
        return 1.0
    }

    private func billingCurrencyCode(for transaction: Transaction) -> String {
        guard let card = transaction.card else {
            return transaction.location.currencyCode
        }

        // Legacy import: billingAmount was saved in transaction currency (no FX conversion).
        if transaction.location != card.issueRegion,
           abs(transaction.billingAmount - transaction.amount) < 0.0001 {
            return transaction.location.currencyCode
        }

        return card.issueRegion.currencyCode
    }
    
    // 计算图表数据
    var chartData: [MonthlyData] {
        let calendar = Calendar.current
        let now = Date()
        var data: [MonthlyData] = []
        
        for i in 0..<12 {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let components = calendar.dateComponents([.year, .month], from: date)
                
                // 筛选
                let monthlyTransactions = transactions.filter { t in
                    let tComponents = calendar.dateComponents([.year, .month], from: t.date)
                    let isSameMonth = tComponents.year == components.year && tComponents.month == components.month
                    let isCardMatch = (selectedCard == nil) || (t.card == selectedCard)
                    return isSameMonth && isCardMatch
                }
                
                // 计算总额 (根据类型区分逻辑)
                let total = monthlyTransactions.reduce(0) { sum, t in
                    let amountToAdd: Double
                    let currencyCode: String
                    // 👇 分支逻辑
                    if type == .expense {
                        amountToAdd = t.billingAmount // 支出算入账金额
                        currencyCode = billingCurrencyCode(for: t)
                    } else {
                        amountToAdd = CashbackService.calculateCashback(for: t) // 返现算返现额
                        currencyCode = t.card?.issueRegion.currencyCode ?? mainCurrencyCode
                    }
                    
                    // 汇率换算
                    let rate = exchangeRate(for: currencyCode)
                    return sum + (amountToAdd / rate)
                }
                
                data.append(MonthlyData(date: date, amount: total))
            }
        }
        return data.reversed()
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                // --- 1. 图表区域 ---
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if let card = selectedCard {
                            // 「招商银行 支出趋势」这种
                            Text("\(card.bankName) \(type.title)趋势")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 16)
                        } else {
                            // 「总支出趋势」这种
                            Text("总\(type.title)趋势")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 16)
                        }
                    }
                    
                    // 动态颜色
                    Text("近12个月累计: \(chartData.reduce(0){ $0 + $1.amount }.formatted(.currency(code: mainCurrencyCode)))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                        .foregroundColor(type.color) // 👇 使用类型颜色
                        .padding(.bottom, 8)
                    
                    Chart(chartData) { item in
                        // 线条
                        LineMark(
                            x: .value("月份", item.date, unit: .month),
                            y: .value("金额", item.amount)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(type.color) // 👇 使用类型颜色
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        
                        // 渐变填充
                        AreaMark(
                            x: .value("月份", item.date, unit: .month),
                            y: .value("金额", item.amount)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [type.color.opacity(0.3), type.color.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        // 数据点
                        PointMark(
                            x: .value("月份", item.date, unit: .month),
                            y: .value("金额", item.amount)
                        )
                        .foregroundStyle(.white)
                        .symbolSize(60)
                        .annotation(position: .top) {
                            if item.amount > 0 {
                                Text("\(Int(item.amount))")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary.opacity(0.7))
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .frame(height: 260)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    // X轴：保持你喜欢的自动间隔
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel(format: .dateTime.month(), centered: true)
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    // Y轴
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel()
                                .font(.system(size: 13))
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // --- 2. 卡片选择列表 ---
                List {
                    Section(header: Text("选择卡片查看详情")) {
                        Button(action: { withAnimation { selectedCard = nil } }) {
                            HStack {
                                ZStack {
                                    Circle().fill(Color.gray.opacity(0.2)).frame(width: 40, height: 40)
                                    Image(systemName: "square.stack.3d.up.fill").foregroundColor(.primary)
                                }
                                Text("所有卡片汇总").foregroundColor(.primary).font(.body)
                                Spacer()
                                if selectedCard == nil {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        ForEach(cards) { card in
                            Button(action: { withAnimation { selectedCard = card } }) {
                                HStack {
                                    Circle()
                                        .fill(LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(card.bankName.prefix(1))
                                                .font(.caption.bold())
                                                .foregroundColor(.white)
                                        )
                                    VStack(alignment: .leading) {
                                        Text(card.bankName).foregroundColor(.primary).font(.body)
                                        Text(card.type).font(.subheadline).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedCard == card {
                                        Image(systemName: "checkmark").foregroundColor(.blue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(
                Text("\(type.title)分析")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
