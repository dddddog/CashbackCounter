import SwiftUI
import SwiftData
import Charts

struct PointSystemView: View {
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var transactions: [Transaction]

    @Query(sort: [SortDescriptor(\PointAdjustment.date, order: .reverse)])
    private var adjustments: [PointAdjustment]

    @Query(sort: [SortDescriptor(\CreditCard.bankName, order: .forward)])
    private var cards: [CreditCard]

    @AppStorage("mainCurrencyCode") private var mainCurrencyCode: String = "CNY"
    @State private var exchangeRates: [String: Double] = [:]
    @State private var showPointLibrary = false
    @State private var showPointAdjustment = false
    @State private var showPointRemoval = false

    var body: some View {
        let summaries = pointSummaries
        let totalValue = totalEstimatedValue(for: summaries)

        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        dashboardHeader(totalValue: totalValue)

                        pointCardSection(summaries: summaries)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("积分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showPointLibrary = true }) {
                            Label("积分库", systemImage: "star.circle")
                        }
                        Button(action: { showPointAdjustment = true }) {
                            Label("手动添加积分", systemImage: "plus")
                        }
                        Button(action: { showPointRemoval = true }) {
                            Label("手动移除积分", systemImage: "minus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 24))
                    }
                }
            }
        }
        .sheet(isPresented: $showPointLibrary) {
            PointLibraryView()
        }
        .sheet(isPresented: $showPointAdjustment) {
            PointAdjustmentEntryView()
        }
        .sheet(isPresented: $showPointRemoval) {
            PointRemovalEntryView()
        }
        .task {
            await refreshRates()
        }
        .onChange(of: mainCurrencyCode) { _, _ in
            Task { await refreshRates() }
        }
    }

    @ViewBuilder
    private func dashboardHeader(totalValue: Double) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("总等值价值（预估）")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(isRatesReady ? formattedNumber(totalValue) : "...")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)

                Text(isRatesReady ? "约合 \(formattedCurrency(totalValue))" : "约合 ...")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private func pointCardSection(summaries: [PointProgramSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("积分卡片")
                .font(.headline)
                .padding(.horizontal, 4)

            if summaries.isEmpty {
                ContentUnavailableView(
                    "暂无积分记录",
                    systemImage: "star.circle",
                    description: Text("新增积分返现交易后，这里会显示累计积分")
                )
                .padding(.top, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(summaries) { summary in
                        NavigationLink {
                            PointDetailView(
                                summary: summary,
                                transactions: transactions,
                                adjustments: adjustments,
                                exchangeRates: exchangeRates,
                                mainCurrencyCode: mainCurrencyCode
                            )
                        } label: {
                            PointSummaryCard(
                                summary: summary,
                                pointsText: formattedPoints(summary.points)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func refreshRates() async {
        let rates = await CurrencyService.getRates(base: mainCurrencyCode)
        await MainActor.run {
            exchangeRates = normalizeRates(rates)
        }
    }

    private var pointSummaries: [PointProgramSummary] {
        var totals: [String: Int] = [:]
        var programs: [String: Point?] = [:]

        for transaction in transactions {
            let points = transaction.pointsEarned
            guard points != 0 else { continue }

            if let program = transaction.card?.pointProgram {
                let key = program.id.uuidString
                totals[key, default: 0] += points
                programs[key] = program
            } else {
                let key = "unassigned"
                totals[key, default: 0] += points
                programs[key] = nil
            }
        }

        for adjustment in adjustments {
            guard adjustment.points != 0 else { continue }
            guard let program = adjustment.pointProgram else { continue }
            let key = program.id.uuidString
            totals[key, default: 0] += adjustment.points
            programs[key] = program
        }

        let pointCards = cards.filter { $0.rewardType == .points }
        for card in pointCards {
            if let program = card.pointProgram {
                let key = program.id.uuidString
                if totals[key] == nil {
                    totals[key] = 0
                    programs[key] = program
                }
            }
        }

        guard !totals.isEmpty else { return [] }

        let cardMap = Dictionary(grouping: pointCards, by: { $0.pointProgram?.id.uuidString ?? "unassigned" })

        return totals.map { key, points in
            let program = programs[key] ?? nil
            let card = cardMap[key]?.first
            let colors = (card?.colors.count ?? 0) >= 2 ? (card?.colors ?? fallbackColors) : fallbackColors
            let bankName = program?.bankName ?? "未分配"
            let pointName = program?.pointName ?? "积分计划"

            return PointProgramSummary(
                id: key,
                program: program,
                bankName: bankName,
                pointName: pointName,
                points: points,
                themeColors: colors
            )
        }
        .sorted { $0.points > $1.points }
    }

    private func estimatedValue(for summary: PointProgramSummary) -> Double {
        guard let program = summary.program, summary.points > 0 else { return 0 }
        let value = Double(summary.points) * program.pointValue
        return convertToMainCurrency(value, from: program.valueCurrencyCode.currencyCode)
    }

    private func totalEstimatedValue(for summaries: [PointProgramSummary]) -> Double {
        summaries.reduce(0) { partial, summary in
            partial + estimatedValue(for: summary)
        }
    }

    private var isRatesReady: Bool {
        !exchangeRates.isEmpty
    }

    private func formattedPoints(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formattedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func formattedCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: mainCurrencyCode))
    }

    private func convertToMainCurrency(_ amount: Double, from currencyCode: String) -> Double {
        guard currencyCode != mainCurrencyCode else { return amount }
        guard let rate = rateForCurrency(currencyCode), rate > 0 else { return amount }
        return amount / rate
    }

    private var fallbackColors: [Color] {
        [Color.gray.opacity(0.35), Color.gray.opacity(0.15)]
    }

    private func normalizeRates(_ rates: [String: Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: rates.map { ($0.key.lowercased(), $0.value) })
    }

    private func rateForCurrency(_ code: String) -> Double? {
        exchangeRates[code.lowercased()] ?? exchangeRates[code]
    }
}

private struct PointProgramSummary: Identifiable {
    let id: String
    let program: Point?
    let bankName: String
    let pointName: String
    let points: Int
    let themeColors: [Color]
}

private struct PointSummaryCard: View {
    let summary: PointProgramSummary
    let pointsText: String

    var body: some View {
        HStack(spacing: 14) {
            PointLogoPlaceholder(
                bankName: summary.bankName,
                colors: summary.themeColors
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.bankName)
                    .font(.headline)
                if !summary.pointName.isEmpty {
                    Text(summary.pointName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(pointsText)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                Text("积分")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))

            if !summary.themeColors.isEmpty {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: summary.themeColors.map { $0.opacity(0.22) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
}

private struct PointLogoPlaceholder: View {
    let bankName: String
    let colors: [Color]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(String(bankName.prefix(1)))
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(width: 48, height: 48)
    }

    private var gradientColors: [Color] {
        if colors.isEmpty {
            return [Color.gray.opacity(0.6), Color.gray.opacity(0.3)]
        }
        return colors
    }
}

private struct PointDetailView: View {
    let summary: PointProgramSummary
    let transactions: [Transaction]
    let adjustments: [PointAdjustment]
    let exchangeRates: [String: Double]
    let mainCurrencyCode: String

    private var accentColor: Color {
        summary.themeColors.first ?? .blue
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                chartCard
            }
            .padding()
        }
        .navigationTitle("积分明细")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PointLogoPlaceholder(
                    bankName: summary.bankName,
                    colors: summary.themeColors
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.bankName)
                        .font(.headline)
                    if !summary.pointName.isEmpty {
                        Text(summary.pointName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前积分")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formattedPoints(totalPoints))
                        .font(.title2.weight(.bold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("估算价值")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(isRatesReady ? formattedCurrency(estimatedValue, code: mainCurrencyCode) : "...")
                        .font(.title3.weight(.semibold))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("近6个月积分变化")
                .font(.headline)
            Text("净变化：\(formattedPoints(netPoints)) 积分")
                .font(.caption)
                .foregroundColor(.secondary)

            Chart(chartData) { item in
                LineMark(
                    x: .value("月份", item.date, unit: .month),
                    y: .value("积分", item.points)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentColor)
                .lineStyle(StrokeStyle(lineWidth: 3))

                AreaMark(
                    x: .value("月份", item.date, unit: .month),
                    y: .value("积分", item.points)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor.opacity(0.3), accentColor.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                PointMark(
                    x: .value("月份", item.date, unit: .month),
                    y: .value("积分", item.points)
                )
                .foregroundStyle(accentColor)
                .symbolSize(40)
            }
            .frame(height: 240)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel(format: .dateTime.month(), centered: true)
                        .font(.caption)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var relatedTransactions: [Transaction] {
        transactions.filter { transaction in
            if let program = summary.program {
                return transaction.card?.pointProgram?.id == program.id
            }
            return transaction.card?.pointProgram == nil
        }
    }

    private var relatedAdjustments: [PointAdjustment] {
        guard let program = summary.program else { return [] }
        return adjustments.filter { $0.pointProgram?.id == program.id }
    }

    private var chartData: [MonthlyPointSnapshot] {
        let calendar = Calendar.current
        let now = Date()

        return (0..<6).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month], from: date)
            let transactionPoints = relatedTransactions.reduce(0) { partial, transaction in
                let tComponents = calendar.dateComponents([.year, .month], from: transaction.date)
                guard tComponents.year == components.year && tComponents.month == components.month else {
                    return partial
                }
                return partial + transaction.pointsEarned
            }
            let adjustmentPoints = relatedAdjustments.reduce(0) { partial, adjustment in
                let aComponents = calendar.dateComponents([.year, .month], from: adjustment.date)
                guard aComponents.year == components.year && aComponents.month == components.month else {
                    return partial
                }
                return partial + adjustment.points
            }
            let total = transactionPoints + adjustmentPoints
            let monthStart = calendar.date(from: components) ?? date
            return MonthlyPointSnapshot(date: monthStart, points: Double(total))
        }
        .reversed()
    }

    private var totalPoints: Int {
        summary.points
    }

    private var netPoints: Int {
        Int(chartData.reduce(0) { $0 + $1.points })
    }

    private var estimatedValue: Double {
        guard let program = summary.program, totalPoints > 0 else { return 0 }
        let value = Double(totalPoints) * program.pointValue
        return convertToMainCurrency(value, from: program.valueCurrencyCode.currencyCode)
    }

    private var isRatesReady: Bool {
        !exchangeRates.isEmpty
    }

    private func formattedPoints(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formattedCurrency(_ value: Double, code: String) -> String {
        value.formatted(.currency(code: code))
    }

    private func convertToMainCurrency(_ amount: Double, from currencyCode: String) -> Double {
        guard currencyCode != mainCurrencyCode else { return amount }
        guard let rate = rateForCurrency(currencyCode), rate > 0 else { return amount }
        return amount / rate
    }

    private func rateForCurrency(_ code: String) -> Double? {
        exchangeRates[code.lowercased()] ?? exchangeRates[code]
    }
}

private struct MonthlyPointSnapshot: Identifiable {
    let id = UUID()
    let date: Date
    let points: Double
}
private struct PointAdjustmentEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Point.bankName, order: .forward)])
    private var points: [Point]

    @State private var selectedPointID: UUID?
    @State private var pointsText: String = ""
    @State private var date: Date = Date()

    var body: some View {
        NavigationView {
            Group {
                if points.isEmpty {
                    ContentUnavailableView(
                        "暂无积分计划",
                        systemImage: "star.circle",
                        description: Text("请先在积分库添加积分计划")
                    )
                } else {
                    Form {
                        Section(header: Text("积分计划")) {
                            Picker("积分计划", selection: $selectedPointID) {
                                ForEach(points) { point in
                                    Text(point.displayName)
                                        .tag(Optional(point.id))
                                }
                            }
                        }

                        Section(header: Text("积分数量")) {
                            HStack {
                                Text("积分")
                                Spacer()
                                TextField("0", text: $pointsText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        Section(header: Text("日期")) {
                            DatePicker("入账日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        }
                    }
                }
            }
            .navigationTitle("手动添加积分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if selectedPointID == nil {
                selectedPointID = points.first?.id
            }
        }
        .onChange(of: points) { _, newPoints in
            if selectedPointID == nil {
                selectedPointID = newPoints.first?.id
            }
        }
    }

    private var selectedPoint: Point? {
        points.first { $0.id == selectedPointID } ?? points.first
    }

    private var pointsValue: Int? {
        let trimmed = pointsText.replacingOccurrences(of: ",", with: "")
        return Int(trimmed)
    }

    private var canSave: Bool {
        guard selectedPoint != nil, let value = pointsValue else { return false }
        return value > 0
    }

    private func save() {
        guard let point = selectedPoint, let value = pointsValue, value > 0 else { return }
        let adjustment = PointAdjustment(pointProgram: point, points: value, date: date)
        context.insert(adjustment)
        dismiss()
    }
}

private struct PointRemovalEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Point.bankName, order: .forward)])
    private var points: [Point]

    @State private var selectedPointID: UUID?
    @State private var pointsText: String = ""
    @State private var date: Date = Date()

    var body: some View {
        NavigationView {
            Group {
                if points.isEmpty {
                    ContentUnavailableView(
                        "暂无积分计划",
                        systemImage: "star.circle",
                        description: Text("请先在积分库添加积分计划")
                    )
                } else {
                    Form {
                        Section(header: Text("积分计划")) {
                            Picker("积分计划", selection: $selectedPointID) {
                                ForEach(points) { point in
                                    Text(point.displayName)
                                        .tag(Optional(point.id))
                                }
                            }
                        }

                        Section(header: Text("移除积分数量")) {
                            HStack {
                                Text("积分")
                                Spacer()
                                TextField("0", text: $pointsText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        Section(header: Text("日期")) {
                            DatePicker("入账日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        }
                    }
                }
            }
            .navigationTitle("手动移除积分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if selectedPointID == nil {
                selectedPointID = points.first?.id
            }
        }
        .onChange(of: points) { _, newPoints in
            if selectedPointID == nil {
                selectedPointID = newPoints.first?.id
            }
        }
    }

    private var selectedPoint: Point? {
        points.first { $0.id == selectedPointID } ?? points.first
    }

    private var pointsValue: Int? {
        let trimmed = pointsText.replacingOccurrences(of: ",", with: "")
        return Int(trimmed)
    }

    private var canSave: Bool {
        guard selectedPoint != nil, let value = pointsValue else { return false }
        return value > 0
    }

    private func save() {
        guard let point = selectedPoint, let value = pointsValue, value > 0 else { return }
        let adjustment = PointAdjustment(pointProgram: point, points: -value, date: date)
        context.insert(adjustment)
        dismiss()
    }
}
