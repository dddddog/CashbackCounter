import SwiftUI
import SwiftData

struct PointLibraryView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Point.bankName, order: .forward)])
    private var points: [Point]

    @State private var pointToEdit: Point?
    @State private var showAddSheet = false

    var body: some View {
        NavigationView {
            List {
                if points.isEmpty {
                    ContentUnavailableView(
                        "暂无积分库",
                        systemImage: "star.circle",
                        description: Text("请添加积分计划以供卡片选择")
                    )
                } else {
                    ForEach(points) { point in
                        Button {
                            pointToEdit = point
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(point.displayName)
                                    .font(.headline)
                                Text("价值: \(String(format: "%.6f", point.pointValue)) \(point.valueCurrencyCode) / 点")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("兑换比例: \(String(point.exchangeRate)) 积分 = 1 \(point.valueCurrencyCode)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let point = points[index]
                            context.delete(point)
                        }
                    }
                }
            }
            .navigationTitle("积分库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                PointEditorView()
            }
            .sheet(item: $pointToEdit) { point in
                PointEditorView(pointToEdit: point)
            }
        }
    }
}

struct PointEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var pointToEdit: Point?

    @State private var bankName: String
    @State private var pointName: String
    @State private var pointValueStr: String
    @State private var exchangeRateStr: String
    @State private var currencyCode: String

    init(pointToEdit: Point? = nil) {
        self.pointToEdit = pointToEdit
        if let point = pointToEdit {
            _bankName = State(initialValue: point.bankName)
            _pointName = State(initialValue: point.pointName)
            _pointValueStr = State(initialValue: String(point.pointValue))
            _exchangeRateStr = State(initialValue: String(point.exchangeRate))
            _currencyCode = State(initialValue: point.valueCurrencyCode)
        } else {
            _bankName = State(initialValue: "")
            _pointName = State(initialValue: "")
            _pointValueStr = State(initialValue: "0.01")
            _exchangeRateStr = State(initialValue: "100")
            _currencyCode = State(initialValue: "CNY")
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("银行", text: $bankName)
                    TextField("积分名称", text: $pointName)
                }

                Section(header: Text("价值与兑换")) {
                    HStack {
                        Text("积分价值")
                        Spacer()
                        TextField("0.01", text: $pointValueStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("兑换比例")
                        Spacer()
                        TextField("100", text: $exchangeRateStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("币种 (如: CNY)", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                }
            }
            .navigationTitle(pointToEdit == nil ? "新增积分计划" : "编辑积分计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { savePoint() }
                        .disabled(bankName.isEmpty || pointName.isEmpty || currencyCode.isEmpty)
                }
            }
        }
    }

    private func savePoint() {
        let pointValue = Double(pointValueStr) ?? 0
        let exchangeRate = Int(exchangeRateStr) ?? 0
        let currency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = pointToEdit {
            existing.bankName = bankName
            existing.pointName = pointName
            existing.pointValue = pointValue
            existing.exchangeRate = exchangeRate
            existing.valueCurrencyCode = currency
        } else {
            let newPoint = Point(
                bankName: bankName,
                pointName: pointName,
                pointValue: pointValue,
                exchangeRate: exchangeRate,
                valueCurrencyCode: currency
            )
            context.insert(newPoint)
        }

        dismiss()
    }
}
