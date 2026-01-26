//
//  AddCardView.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/23/25.
//

import SwiftUI
import SwiftData
// AddCardView.swift
struct AddCardView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    
    @State private var viewModel: AddCardViewModel
    var onSaved: (() -> Void)?

    init(repository: TransactionRepositoryProtocol, template: CardTemplate? = nil, cardToEdit: CreditCard? = nil, onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        self._viewModel = State(initialValue: AddCardViewModel(
            repository: repository,
            cardToEdit: cardToEdit,
            template: template
        ))
    }
    
    var body: some View {
        NavigationView {
            Form {
                // 1. 实时预览
                Section {
                    CreditCardView(
                        bankName: viewModel.bankName.isEmpty ? "银行名称" : viewModel.bankName,
                        type: viewModel.cardType.isEmpty ? "卡种" : viewModel.cardType,
                        endNum: viewModel.endNum.isEmpty ? "8888" : viewModel.endNum,
                        colors: [viewModel.color1, viewModel.color2]
                    )
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
                
                // 2. 基本信息
                Section(header: Text("基本信息")) {
                    TextField("银行 (如: 招商银行)", text: $viewModel.bankName)
                    TextField("卡种 (如: 运通白金)", text: $viewModel.cardType)
                    TextField("尾号 (后四位)", text: $viewModel.endNum)
                        .keyboardType(.numberPad)
                        .onChange(of: viewModel.endNum) { _, newValue in
                            if newValue.count > 4 { viewModel.endNum = String(newValue.prefix(4)) }
                        }
                    
                    HStack {
                        Text("还款日提醒 (每月)")
                        Spacer()
                        TextField("无", text: $viewModel.repaymentDayStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("日").foregroundColor(.secondary)
                    }
                }
                
                // 3. 样式与周期
                Section(header: Text("卡面风格")) {
                    ColorPicker("渐变色 1", selection: $viewModel.color1)
                    ColorPicker("渐变色 2", selection: $viewModel.color2)
                }
                
                Section(header: Text("返现上限周期")) {
                    Picker("周期", selection: $viewModel.capPeriod) {
                        Text("按月").tag(CapPeriod.monthly)
                        Text("按年").tag(CapPeriod.yearly)
                    }
                    .pickerStyle(.segmented)
                }
                
                // 4. 返现规则
                Section(header: Text("基础返现 (所有消费)")) {
                    Picker("发行地区", selection: $viewModel.region) {
                        ForEach(Region.allCases, id: \.self) { r in
                            Text("\(r.icon) \(r.rawValue)").tag(r)
                        }
                    }
                    
                    rateAndCapRow(title: "本币返现", rate: $viewModel.defaultRateStr, cap: $viewModel.localBaseCapStr)
                    rateAndCapRow(title: "外币返现", rate: $viewModel.foreignRateStr, cap: $viewModel.foreignBaseCapStr, placeholder: "同本币")
                }
                
                Section(header: Text("类别加成 (额外叠加)")) {
                    CategoryInputRow(name: "餐饮", rate: $viewModel.diningRateStr, cap: $viewModel.diningCapStr)
                    CategoryInputRow(name: "超市", rate: $viewModel.groceryRateStr, cap: $viewModel.groceryCapStr)
                    CategoryInputRow(name: "出行", rate: $viewModel.travelRateStr, cap: $viewModel.travelCapStr)
                    CategoryInputRow(name: "数码", rate: $viewModel.digitalRateStr, cap: $viewModel.digitalCapStr)
                    CategoryInputRow(name: "其他", rate: $viewModel.otherRateStr, cap: $viewModel.otherCapStr)
                }
            }
            .navigationTitle(viewModel.bankName.isEmpty ? "添加信用卡" : "编辑卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if viewModel.save() {
                            onSaved?()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.bankName.isEmpty || viewModel.cardType.isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - 辅助 UI 组件
extension AddCardView {
    @ViewBuilder
    private func rateAndCapRow(title: String, rate: Binding<String>, cap: Binding<String>, placeholder: String = "1.0") -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(title)率 (%)")
                Spacer()
                TextField(placeholder, text: rate)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
            HStack {
                Text("\(title)\(viewModel.capPeriod == .monthly ? "月" : "年")上限")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                TextField("无上限", text: cap)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        }
    }

    struct CategoryInputRow: View {
        let name: String
        @Binding var rate: String
        @Binding var cap: String
        
        var body: some View {
            HStack {
                Text(name).fontWeight(.medium)
                Spacer()
                Text("加成%").font(.caption).foregroundColor(.gray)
                TextField("0", text: $rate)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                    .padding(5)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(5)
                
                Text("上限").font(.caption).foregroundColor(.gray)
                TextField("无", text: $cap)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .padding(5)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(5)
            }
            .padding(.vertical, 4)
        }
    }
}
