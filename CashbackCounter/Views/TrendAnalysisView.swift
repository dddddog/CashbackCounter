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
    @State private var selectedDate: Date? = nil
    
    // 可滚动 & 可缩放图表状态
    @State private var visibleMonths: Double = 6.0
    @State private var baseVisibleMonths: Double = 6.0

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
    
    // 计算图表数据 — 覆盖全部历史月份
    var chartData: [MonthlyData] {
        let calendar = Calendar.current
        let now = Date()
        
        // 确定最早的交易月份
        let relevantTransactions: [Transaction]
        if let selectedCard {
            relevantTransactions = transactions.filter { $0.card == selectedCard }
        } else {
            relevantTransactions = transactions
        }
        
        guard let earliest = relevantTransactions.map({ $0.date }).min() else { return [] }
        
        let nowComponents = calendar.dateComponents([.year, .month], from: now)
        let earliestComponents = calendar.dateComponents([.year, .month], from: earliest)
        let totalMonths = max(1, (nowComponents.year! - earliestComponents.year!) * 12
                               + (nowComponents.month! - earliestComponents.month!) + 1)
        
        var data: [MonthlyData] = []
        
        for i in 0..<totalMonths {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let components = calendar.dateComponents([.year, .month], from: date)
                
                // 使用规范化日期 (每月1号) 以获得更好的图表显示
                guard let normalizedDate = calendar.date(from: components) else { continue }
                
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
                
                data.append(MonthlyData(date: normalizedDate, amount: total))
            }
        }
        return data.reversed()
    }

    // MARK: - 统计数据

    private var totalMonthCount: Int { max(chartData.count, 1) }

    private var totalAmount: Double {
        chartData.reduce(0) { $0 + $1.amount }
    }

    private var monthRangeText: String {
        guard let start = chartData.first?.date, let end = chartData.last?.date else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy/MM"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private var peakMonthData: MonthlyData? {
        chartData.max(by: { $0.amount < $1.amount })
    }

    private func peakMonthLabel(for date: Date?) -> String {
        guard let date else { return "暂无数据" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.dateFormat = "MM月峰值"
        return formatter.string(from: date)
    }

    private func formattedCurrencyInteger(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = mainCurrencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    private var highlightedData: MonthlyData? {
        guard let selectedDate else { return nil }
        return chartData.min(by: {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        })
    }

    private func formattedCurrency(_ amount: Double) -> String {
        amount.formatted(.currency(code: mainCurrencyCode))
    }

    private func axisLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        if month == 1 {
            return date.formatted(.dateTime.year().month(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated))
    }

    // MARK: - 可滚动/缩放图表计算属性

    /// 可见范围对应的秒数 (用于 chartXVisibleDomain)
    private var visibleDomainLength: Int {
        Int(visibleMonths * 30.44 * 24 * 60 * 60)
    }

    /// 图表初始滚动位置：最近 N 个月的起始日期
    private var initialScrollDate: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: -Int(visibleMonths), to: Date()) ?? Date()
    }

    /// X 轴标签间距 — 根据可见月数动态调整
    private var axisStride: Int {
        if visibleMonths <= 6 { return 1 }
        if visibleMonths <= 12 { return 2 }
        if visibleMonths <= 24 { return 3 }
        return 6
    }

    /// 当前激活的时间范围标签
    private var activeRangeLabel: String {
        let m = Int(visibleMonths.rounded())
        if m >= totalMonthCount { return "ALL" }
        if abs(visibleMonths - 12) < 0.5 { return "1Y" }
        if abs(visibleMonths - 6) < 0.5 { return "6M" }
        if abs(visibleMonths - 3) < 0.5 { return "3M" }
        return "\(m)M"
    }

    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                // --- 1. 图表区域 ---
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let card = selectedCard {
                            Text("\(card.bankName) \(type.title)趋势")
                                .font(.headline)
                        } else {
                            Text("总\(type.title)趋势")
                                .font(.headline)
                        }
                        Spacer()
                        if let highlighted = highlightedData {
                            Text(highlighted.date, format: .dateTime.year().month())
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // 时间范围快捷按钮 (类似股票 App)
                    HStack(spacing: 6) {
                        ForEach(["3M", "6M", "1Y", "ALL"], id: \.self) { label in
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    let months: Double
                                    switch label {
                                    case "3M": months = 3
                                    case "6M": months = 6
                                    case "1Y": months = 12
                                    default: months = Double(totalMonthCount)
                                    }
                                    visibleMonths = min(months, Double(totalMonthCount))
                                    baseVisibleMonths = visibleMonths
                                    selectedDate = nil
                                }
                            } label: {
                                Text(label)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(activeRangeLabel == label ? type.color.opacity(0.15) : Color.clear)
                                    )
                                    .foregroundColor(activeRangeLabel == label ? type.color : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // 三列式的数据仪表盘卡片网格
                    HStack(spacing: 8) {
                        statCard(
                            title: "全部累计",
                            value: formattedCurrencyInteger(totalAmount),
                            subtitle: monthRangeText.isEmpty ? nil : monthRangeText,
                            highlightColor: type.color
                        )
                        statCard(
                            title: "月均水平",
                            value: formattedCurrencyInteger(totalAmount / Double(totalMonthCount)),
                            subtitle: "月均\(type.title)"
                        )
                        statCard(
                            title: "单月最高",
                            value: formattedCurrencyInteger(peakMonthData?.amount ?? 0.0),
                            subtitle: peakMonthLabel(for: peakMonthData?.date)
                        )
                    }
                    .padding(.horizontal)
                    
                    Chart {
                        ForEach(chartData) { item in
                            // 线条
                            LineMark(
                                x: .value("月份", item.date, unit: .month),
                                y: .value("金额", item.amount)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(type.color.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                            
                            // 渐变填充
                            AreaMark(
                                x: .value("月份", item.date, unit: .month),
                                y: .value("金额", item.amount)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [type.color.opacity(0.25), type.color.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            
                            // 数据点
                            PointMark(
                                x: .value("月份", item.date, unit: .month),
                                y: .value("金额", item.amount)
                            )
                            .foregroundStyle(type.color)
                            .symbolSize(16)
                        }

                        if let highlighted = highlightedData {
                            RuleMark(
                                x: .value("选中月份", highlighted.date, unit: .month)
                            )
                            .foregroundStyle(.secondary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            PointMark(
                                x: .value("月份", highlighted.date, unit: .month),
                                y: .value("金额", highlighted.amount)
                            )
                            .symbolSize(80)
                            .foregroundStyle(type.color)
                            .annotation(position: .top, alignment: .center) {
                                VStack(alignment: .center, spacing: 2) {
                                    Text(highlighted.date, format: .dateTime.month(.abbreviated))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Text(formattedCurrency(highlighted.amount))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.regularMaterial)
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                )
                            }
                        }
                    }
                    .frame(height: 240)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    // 水平滚动 — 像股票图表一样可以左右拖动
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleDomainLength)
                    .chartScrollPosition(initialX: initialScrollDate)
                    // 触摸选择数据点 (长按+拖动显示十字线，快速滑动则滚动)
                    .chartXSelection(value: $selectedDate)
                    // 捏合缩放 — 两指缩放可见时间范围
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let newMonths = baseVisibleMonths / value.magnification
                                visibleMonths = max(2, min(Double(max(totalMonthCount, 2)), newMonths))
                            }
                            .onEnded { _ in
                                baseVisibleMonths = visibleMonths
                            }
                    )
                    // X轴：根据可见月数动态调整标签间距
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month, count: axisStride)) { value in
                            AxisTick()
                            if let date = value.as(Date.self) {
                                AxisValueLabel {
                                    Text(axisLabel(for: date))
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                        }
                    }
                    // Y轴：使用 compactName 紧凑表示以释放绘制区域宽度
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(Color.secondary.opacity(0.15))
                            if let amount = value.as(Double.self) {
                                AxisValueLabel {
                                    Text(amount.formatted(.currency(code: mainCurrencyCode).notation(.compactName)))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                            }
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(DesignConstants.CornerRadius.extraLarge)
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
    
    @ViewBuilder
    private func statCard(title: String, value: String, subtitle: String? = nil, highlightColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(highlightColor ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Spacer().frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
}
