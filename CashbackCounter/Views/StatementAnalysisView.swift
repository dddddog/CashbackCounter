import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StatementAnalysisEntryView: View {
    @State private var showImporter = false
    @State private var statement: StatementMetadata?
    @State private var statementVersion = 0
    @State private var errorMessage: String?
    @State private var isParsing = false

    var body: some View {
        NavigationView {
            Group {
                if let statement {
                    StatementAnalysisView(statement: statement)
                        .id(statementVersion)
                } else {
                    ContentUnavailableView(
                        "尚未导入结单",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("上传结单PDF以开始对账")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .overlay { parsingOverlay }
            .navigationTitle("结单分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: {
                        Label("上传结单", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "无法读取文件权限"
                    return
                }
                isParsing = true
                defer {
                    url.stopAccessingSecurityScopedResource()
                    isParsing = false
                }

                let metadata = StatementParser().parse(from: url)
                guard let metadata else {
                    errorMessage = "解析失败"
                    return
                }
                statement = metadata
                statementVersion += 1
            case .failure(let error):
                errorMessage = "选择文件失败：\(error.localizedDescription)"
            }
        }
        .alert("导入失败", isPresented: errorBinding) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var parsingOverlay: some View {
        if isParsing {
            ProgressView("解析中...")
                .padding(16)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }
}

struct StatementAnalysisView: View {
    let statement: StatementMetadata

    @Query private var transactions: [Transaction]
    @Query(sort: [
        SortDescriptor(\CreditCard.bankName, order: .forward),
        SortDescriptor(\CreditCard.type, order: .forward),
        SortDescriptor(\CreditCard.endNum, order: .forward)
    ])
    private var cards: [CreditCard]
    @State private var selectedMissing: ImportedTransaction?
    @State private var selectedCardIndex: Int = 0
    @State private var analyzedTransactions: [ImportedTransaction] = []
    @State private var detectedCardLast4: String?
    @State private var detectedCardName: String?
    @State private var isDetectingCard = false
    @State private var isAnalyzingTransactions = false
    @State private var didApplyDetectedCard = false
    @State private var didAutoAnalyze = false

    private var displayedTransactions: [ImportedTransaction] {
        analyzedTransactions.isEmpty ? statement.transactions : analyzedTransactions
    }

    private var report: ReconciliationReport {
        ReconciliationEngine().compare(imported: displayedTransactions, existing: transactions)
    }

    private var selectedCard: CreditCard? {
        guard cards.indices.contains(selectedCardIndex) else { return nil }
        return cards[selectedCardIndex]
    }

    private var detectedCardText: String? {
        var parts: [String] = []
        if let detectedCardName, !detectedCardName.isEmpty {
            parts.append(detectedCardName)
        }
        if let detectedCardLast4, !detectedCardLast4.isEmpty {
            parts.append("**** \(detectedCardLast4)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 12) {
            StatementSummaryCard(
                metadata: statement,
                report: report,
                cards: cards,
                selectedCardIndex: $selectedCardIndex,
                detectedCardText: detectedCardText,
                isDetectingCard: isDetectingCard,
                isAnalyzingTransactions: isAnalyzingTransactions
            )
                .padding(.horizontal)

            List {
                Section(header: missingHeader) {
                    if report.missingInApp.isEmpty {
                        Text("No missing transactions")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(report.missingInApp) { item in
                            ReconciliationRow(
                                transaction: item,
                                status: .missing,
                                onAdd: { selectedMissing = item }
                            )
                        }
                    }
                }

                Section(header: matchedHeader) {
                    if report.matched.isEmpty {
                        Text("No matched transactions")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(report.matched) { item in
                            ReconciliationRow(
                                transaction: item,
                                status: .matched,
                                onAdd: nil
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Statement Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await detectStatementCardIfNeeded()
            await autoAnalyzeIfNeeded()
        }
        .onChange(of: cards.count) { _, _ in
            applyDetectedCardSelectionIfNeeded()
        }
        .onChange(of: detectedCardLast4) { _, _ in
            applyDetectedCardSelectionIfNeeded()
        }
        .onChange(of: detectedCardName) { _, _ in
            applyDetectedCardSelectionIfNeeded()
        }
        .sheet(item: $selectedMissing) { item in
            AddTransactionView(
                transaction: nil,
                image: nil,
                prefillMerchant: item.merchant,
                prefillAmount: item.foreignAmount ?? item.billingAmount,
                prefillBillingAmount: item.billingAmount,
                prefillDate: item.transactionDate,
                prefillCategory: item.category,
                prefillLocation: item.region,
                prefillPaymentMethod: item.paymentMethod,
                prefillCardLast4: selectedCard?.endNum,
                onSaved: nil
            )
        }
    }

    private var missingHeader: some View {
        Text("Missing in App (Action Required)")
            .foregroundColor(.orange)
    }

    private var matchedHeader: some View {
        Text("Already Recorded")
            .foregroundColor(.green)
    }

    @MainActor
    private func detectStatementCardIfNeeded() async {
        guard !isDetectingCard else { return }
        guard detectedCardLast4 == nil && detectedCardName == nil else { return }
        guard let statementText = statement.statementText, !statementText.isEmpty else { return }
        let promptText = statementCardPromptText(from: statementText)

        isDetectingCard = true
        defer { isDetectingCard = false }

        do {
            let metadata = try await ReceiptParser().parseStatementCard(text: promptText)
            detectedCardLast4 = metadata.cardLast4?.trimmingCharacters(in: .whitespacesAndNewlines)
            detectedCardName = metadata.cardName?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Statement card parse failed: \(error)")
        }
    }

    private func applyDetectedCardSelectionIfNeeded() {
        guard !didApplyDetectedCard else { return }
        guard !cards.isEmpty else { return }

        if let detectedCardLast4 {
            let cleanedLast4 = detectedCardLast4.filter { $0.isNumber }
            if let index = cards.firstIndex(where: { $0.endNum == cleanedLast4 }) {
                selectedCardIndex = index
                didApplyDetectedCard = true
                return
            }
        }

        guard let detectedCardName, !detectedCardName.isEmpty else { return }
        if let index = cards.firstIndex(where: { card in
            card.bankName.localizedCaseInsensitiveContains(detectedCardName) ||
            card.type.localizedCaseInsensitiveContains(detectedCardName)
        }) {
            selectedCardIndex = index
            didApplyDetectedCard = true
        }
    }

    @MainActor
    private func analyzeTransactions() async {
        guard !isAnalyzingTransactions else { return }
        guard !statement.transactions.isEmpty else { return }
        if analyzedTransactions.count == statement.transactions.count {
            didAutoAnalyze = true
            return
        }

        isAnalyzingTransactions = true
        defer { isAnalyzingTransactions = false }

        var updated: [ImportedTransaction] = []
        let parser = ReceiptParser()

        for transaction in statement.transactions {
            if let matchedTransaction = matchedTransaction(for: transaction) {
                let enriched = transaction.withAnalysis(
                    region: matchedTransaction.location,
                    paymentMethod: matchedTransaction.paymentMethod,
                    category: matchedTransaction.category,
                    foreignAmount: matchedTransaction.amount
                )
                updated.append(enriched)
                continue
            }

            let prompt = transactionPromptText(for: transaction)
            do {
                let metadata = try await parser.parseStatementTransaction(text: prompt)
                let enriched = transaction.withAnalysis(
                    region: metadata.region,
                    paymentMethod: metadata.paymentMethod,
                    category: metadata.category,
                    foreignAmount: metadata.foreignAmount
                )
                updated.append(enriched)
            } catch {
                print("Statement transaction parse failed: \(error)")
                updated.append(transaction)
            }
        }

        analyzedTransactions = updated
        didAutoAnalyze = true
    }

    @MainActor
    private func autoAnalyzeIfNeeded() async {
        guard !didAutoAnalyze else { return }
        await analyzeTransactions()
    }

    private func transactionPromptText(for transaction: ImportedTransaction) -> String {
        let dateText = Self.transactionDateFormatter.string(from: transaction.transactionDate)
        var lines: [String] = [
            "Merchant: \(transaction.merchant)",
            "BillingAmount: \(String(format: "%.2f", transaction.billingAmount))",
        ]

        if let currency = transaction.region?.currencyCode, let amount = transaction.foreignAmount {
            lines.append("Foreign: \(currency) \(String(format: "%.2f", amount))")
        }

        if let rawText = transaction.rawText, !rawText.isEmpty {
            var trimmed = rawText
            let maxChars = 1200
            if trimmed.count > maxChars {
                trimmed = String(trimmed.prefix(maxChars))
            }
            lines.append("Statement block:\n\(trimmed)")
        }


        return lines.joined(separator: "\n")
    }

    private func matchedTransaction(for imported: ImportedTransaction) -> Transaction? {
        let calendar = Calendar.current
        return transactions.first { transaction in
            amountsMatch(imported.billingAmount, transaction.billingAmount) &&
            datesWithinRange(imported.transactionDate, transaction.date, calendar: calendar)
        }
    }

    private func amountsMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.0001
    }

    private func datesWithinRange(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        let leftDay = calendar.startOfDay(for: lhs)
        let rightDay = calendar.startOfDay(for: rhs)
        let dayDiff = calendar.dateComponents([.day], from: leftDay, to: rightDay).day ?? Int.max
        return abs(dayDiff) <= 3
    }

    private func statementCardPromptText(from fullText: String) -> String {
        let lines = fullText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let keywords = [
            "card", "card number", "card no", "ending", "account",
            "xxxx", "****", "hsbc", "visa", "mastercard", "amex"
        ]

        var selectedIndexes: Set<Int> = []
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let hasKeyword = keywords.contains { lower.contains($0) }
            let hasDigits = line.contains(where: { $0.isNumber })
            if hasKeyword || hasDigits && (lower.contains("****") || lower.contains("xxxx")) {
                selectedIndexes.insert(index)
                if index > 0 { selectedIndexes.insert(index - 1) }
                if index + 1 < lines.count { selectedIndexes.insert(index + 1) }
            }
        }

        var selectedLines: [String] = []
        if selectedIndexes.isEmpty {
            selectedLines = Array(lines.prefix(80))
        } else {
            selectedLines = selectedIndexes.sorted().map { lines[$0] }
        }

        var prompt = selectedLines.joined(separator: "\n")
        let maxChars = 2000
        if prompt.count > maxChars {
            prompt = String(prompt.prefix(maxChars))
        }
        return prompt
    }

    private static let transactionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

private struct StatementSummaryCard: View {
    let metadata: StatementMetadata
    let report: ReconciliationReport
    let cards: [CreditCard]
    @Binding var selectedCardIndex: Int
    let detectedCardText: String?
    let isDetectingCard: Bool
    let isAnalyzingTransactions: Bool

    private var totalCount: Int {
        metadata.transactions.count
    }



    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statement Summary")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(balanceText)
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matched: \(report.matched.count) items")
                        .font(.subheadline)
                    Text("Missing: \(report.missingInApp.count) items")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }

                Spacer()
            }

            if cards.isEmpty {
                Text("请先添加信用卡")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Text("结单卡")
                        .font(.subheadline)
                    Spacer()
                    Picker("结单卡", selection: $selectedCardIndex) {
                        ForEach(cards.indices, id: \.self) { index in
                            let card = cards[index]
                            Text("\(card.bankName) \(card.type)")
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .truncationMode(.middle)
                                .tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if let detectedCardText, !detectedCardText.isEmpty {
                HStack(spacing: 6) {
                    if isDetectingCard {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text("自动识别: \(detectedCardText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if isDetectingCard {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在识别结单卡...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isAnalyzingTransactions {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("识别交易中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blue.opacity(0.1))
        )
    }

    private var balanceText: String {
        guard let total = metadata.totalBalance else { return "--" }
        return formatAmount(total)
    }

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

private struct ReconciliationRow: View {
    enum Status {
        case missing
        case matched
    }

    let transaction: ImportedTransaction
    let status: Status
    let onAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            DateBadge(date: transaction.transactionDate)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchant)
                    .font(.body)
                    .lineLimit(1)

                if let foreignText = foreignAmountText {
                    Text(foreignText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let analysisText = analysisDetailText {
                    Text(analysisText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(formatAmount(transaction.billingAmount))
                    .fontWeight(.semibold)

                switch status {
                case .missing:
                    Button {
                        onAdd?()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                case .matched:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
            }
        }
        .opacity(status == .matched ? 0.6 : 1)
        .padding(.vertical, 4)
    }

    private var foreignAmountText: String? {
        guard let amount = transaction.foreignAmount,
              let currency = transaction.region?.currencyCode else {
            return nil
        }
        return "\(currency) \(String(format: "%.2f", amount))"
    }

    private var analysisDetailText: String? {
        var parts: [String] = []
        if let region = transaction.region {
            parts.append("\(region.icon) \(region.rawValue)")
        }
        if let paymentMethod = transaction.paymentMethod {
            parts.append(paymentMethod.displayName)
        }
        if let category = transaction.category {
            parts.append(category.displayName)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }
}

private struct DateBadge: View {
    let date: Date

    var body: some View {
        VStack(spacing: 2) {
            Text(Self.dayFormatter.string(from: date))
                .font(.headline)
            Text(Self.monthFormatter.string(from: date))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 44)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
}
private extension ImportedTransaction {
    func withAnalysis(
        region: Region?,
        paymentMethod: PaymentMethod?,
        category: Category?,
        foreignAmount: Double?
    ) -> ImportedTransaction {
        let resolvedForeignAmount = foreignAmount ?? self.foreignAmount
        let resolvedRegion = region ?? self.region
        let resolvedForeignCurrency = resolvedRegion?.currencyCode
        return ImportedTransaction(
            id: id,
            transactionDate: transactionDate,
            postDate: postDate,
            merchant: merchant,
            billingAmount: billingAmount,
            foreignAmount: resolvedForeignAmount,
            foreignCurrency: resolvedForeignCurrency,
            region: region,
            paymentMethod: paymentMethod,
            category: category,
            rawText: rawText
        )
    }
}

