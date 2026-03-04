//
//  AddCardView.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/23/25.
//

import SwiftUI
import SwiftData

struct AddCardView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @StateObject private var imageManager = ImageDownloadManager()
    @State private var cardImageData: Data? = nil
    @Query(sort: [SortDescriptor(\Point.bankName, order: .forward)])
    private var points: [Point]
    
    // 1. 接收要编辑的卡片 (如果是 nil 就是添加模式)
    var cardToEdit: CreditCard?
    private let template: CardTemplate?
    var onSaved: (() -> Void)? = nil
    
    // --- 表单状态 ---
    @State private var bankName: String
    @State private var cardType: String
    @State private var endNum: String
    
    @State private var color1: Color
    @State private var capPeriod: CapPeriod
    @State private var color2: Color
    @State private var region: Region
    
    @State private var defaultRateStr: String
    @State private var foreignRateStr: String
    
    // 类别加成费率
    @State private var diningRateStr: String = ""
    @State private var groceryRateStr: String = ""
    @State private var travelRateStr: String = ""
    @State private var digitalRateStr: String = ""
    @State private var otherRateStr: String = ""
    
    // 基础上限
    @State private var localBaseCapStr: String = ""
    @State private var foreignBaseCapStr: String = ""
    
    // 类别加成上限
    @State private var diningCapStr: String = ""
    @State private var groceryCapStr: String = ""
    @State private var travelCapStr: String = ""
    @State private var digitalCapStr: String = ""
    @State private var otherCapStr: String = ""
    
    // 还款日
    @State private var repaymentDayStr: String = ""
    
    // 支付方式 (Payment Method) 的状态变量
    @State private var paymentMethodRates: [PaymentMethod: Double]
    @State private var paymentCaps: [PaymentMethod: Double]
    @State private var rewardType: RewardType
    @State private var selectedPointID: UUID?
    @State private var showPointLibrary = false
    
    // --- 2. 核心：自定义初始化 ---
    init(template: CardTemplate? = nil, cardToEdit: CreditCard? = nil, onSaved: (() -> Void)? = nil) {
        self.cardToEdit = cardToEdit
        self.template = template
        self.onSaved = onSaved
        
        // 逻辑 A: 编辑模式 -> 填充旧数据
        if let card = cardToEdit {
            _cardImageData = State(initialValue: card.cardImageData)
            
            _bankName = State(initialValue: card.bankName)
            _cardType = State(initialValue: card.type)
            _endNum = State(initialValue: card.endNum)
            if card.repaymentDay > 0 {
                _repaymentDayStr = State(initialValue: String(card.repaymentDay))
            }
            
            if card.colors.count >= 2 {
                _color1 = State(initialValue: card.colors[0])
                _color2 = State(initialValue: card.colors[1])
            } else {
                _color1 = State(initialValue: .blue)
                _color2 = State(initialValue: .purple)
            }
            
            _region = State(initialValue: card.issueRegion)
            _capPeriod = State(initialValue: card.capPeriod)
            
            _defaultRateStr = State(initialValue: String(card.defaultRate * 100))
            if let foreignRate = card.foreignCurrencyRate {
                _foreignRateStr = State(initialValue: String(foreignRate * 100))
            } else {
                _foreignRateStr = State(initialValue: "")
            }
            
            if let rate = card.specialRates[.dining] { _diningRateStr = State(initialValue: String(rate * 100)) }
            if let rate = card.specialRates[.grocery] { _groceryRateStr = State(initialValue: String(rate * 100)) }
            if let rate = card.specialRates[.travel] { _travelRateStr = State(initialValue: String(rate * 100)) }
            if let rate = card.specialRates[.digital] { _digitalRateStr = State(initialValue: String(rate * 100)) }
            if let rate = card.specialRates[.other] { _otherRateStr = State(initialValue: String(rate * 100)) }
            
            if card.localBaseCap > 0 { _localBaseCapStr = State(initialValue: String(format: "%.0f", card.localBaseCap)) }
            if card.foreignBaseCap > 0 { _foreignBaseCapStr = State(initialValue: String(format: "%.0f", card.foreignBaseCap)) }
            
            if let cap = card.categoryCaps[.dining], cap > 0 { _diningCapStr = State(initialValue: String(format: "%.0f", cap)) }
            if let cap = card.categoryCaps[.grocery], cap > 0 { _groceryCapStr = State(initialValue: String(format: "%.0f", cap)) }
            if let cap = card.categoryCaps[.travel], cap > 0 { _travelCapStr = State(initialValue: String(format: "%.0f", cap)) }
            if let cap = card.categoryCaps[.digital], cap > 0 { _digitalCapStr = State(initialValue: String(format: "%.0f", cap)) }
            if let cap = card.categoryCaps[.other], cap > 0 { _otherCapStr = State(initialValue: String(format: "%.0f", cap)) }
            
            let ratesForUI = card.paymentMethodRates.mapValues { $0 * 100}
            _paymentMethodRates = State(initialValue: ratesForUI)
            _paymentCaps = State(initialValue: card.paymentCaps)
            _rewardType = State(initialValue: card.rewardType)
            _selectedPointID = State(initialValue: card.pointProgram?.id)
            
        }
        // 逻辑 B: 模板模式 -> 填充模板数据
        else if let template = template {
            _bankName = State(initialValue: template.bankName)
            _cardType = State(initialValue: template.type)
            _endNum = State(initialValue: "8888")
            
            if template.localBaseCap > 0 {
                _localBaseCapStr = State(initialValue: String(format: "%.0f", template.localBaseCap))
            }
            if template.foreignBaseCap > 0 {
                _foreignBaseCapStr = State(initialValue: String(format: "%.0f", template.foreignBaseCap))
            }
            
            if template.colors.count >= 2 {
                _color1 = State(initialValue: Color(hex: template.colors[0]))
                _color2 = State(initialValue: Color(hex: template.colors[1]))
            } else {
                _color1 = State(initialValue: .blue)
                _color2 = State(initialValue: .purple)
            }
            
            if let cap = template.categoryCaps[.dining], cap > 0 { _diningCapStr = State(initialValue: String(format: "%.0f", cap)) }
            if let cap = template.categoryCaps[.grocery], cap > 0 { _groceryCapStr = State(initialValue: String(format: "%.0f", cap)) }
            if let cap = template.categoryCaps[.travel], cap > 0 { _travelCapStr = State(initialValue: String(format: "%.0f", cap)) }
            if let cap = template.categoryCaps[.digital], cap > 0 { _digitalCapStr = State(initialValue: String(format: "%.0f", cap)) }
            if let cap = template.categoryCaps[.other], cap > 0 { _otherCapStr = State(initialValue: String(format: "%.0f", cap)) }

            _region = State(initialValue: template.region)
            _capPeriod = State(initialValue: template.capPeriod)
            
            let defStr = String(format: "%.1f", template.defaultRate)
            _defaultRateStr = State(initialValue: defStr.replacingOccurrences(of: ".0", with: ""))

            if let fr = template.foreignCurrencyRate {
                let frStr = String(format: "%.1f", fr)
                _foreignRateStr = State(initialValue: frStr.replacingOccurrences(of: ".0", with: ""))
            } else {
                _foreignRateStr = State(initialValue: "")
            }
            
            if let dining = template.specialRate[.dining] {
                let s = String(format: "%.1f", dining).replacingOccurrences(of: ".0", with: "")
                _diningRateStr = State(initialValue: s)
            }
            if let grocery = template.specialRate[.grocery] {
                let s = String(format: "%.1f", grocery).replacingOccurrences(of: ".0", with: "")
                _groceryRateStr = State(initialValue: s)
            }
            if let travel = template.specialRate[.travel] {
                let s = String(format: "%.1f", travel).replacingOccurrences(of: ".0", with: "")
                _travelRateStr = State(initialValue: s)
            }
            if let digital = template.specialRate[.digital] {
                let s = String(format: "%.1f", digital).replacingOccurrences(of: ".0", with: "")
                _digitalRateStr = State(initialValue: s)
            }
            if let other = template.specialRate[.other] {
                let s = String(format: "%.1f", other).replacingOccurrences(of: ".0", with: "")
                _otherRateStr = State(initialValue: s)
            }
            
            _paymentMethodRates = State(initialValue: template.paymentMethodRates)
            _paymentCaps = State(initialValue: template.paymentCaps)
            _rewardType = State(initialValue: .cashback)
            _selectedPointID = State(initialValue: nil)
            
            
        }
        // 逻辑 C: 纯新建模式
        else {
            _bankName = State(initialValue: "")
            _cardType = State(initialValue: "")
            _endNum = State(initialValue: "")
            _color1 = State(initialValue: .blue)
            _color2 = State(initialValue: .purple)
            _region = State(initialValue: .cn)
            _capPeriod = State(initialValue: .monthly)
            _defaultRateStr = State(initialValue: "1.0")
            _foreignRateStr = State(initialValue: "")
            
            _paymentMethodRates = State(initialValue: [:])
            _paymentCaps = State(initialValue: [:])
            _rewardType = State(initialValue: .cashback)
            _selectedPointID = State(initialValue: nil)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // 1. 实时预览
                Section {
                    VStack(spacing: 12) {
                        CreditCardView(
                            bankName: bankName.isEmpty ? "银行名称" : bankName,
                            type: cardType.isEmpty ? "卡种" : cardType,
                            endNum: endNum.isEmpty ? "8888" : endNum,
                            colors: [color1, color2],
                            cardImageData: cardImageData
                        )
                        
                        if imageManager.isDownloading {
                            ProgressView("正在下载卡面...", value: imageManager.downloadProgress, total: 1.0)
                                .padding(.top, 5)
                        }
                        
                        if let error = imageManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
                
                // 2. 基本信息
                Section(header: Text("基本信息")) {
                    TextField("银行 (如: 招商银行)", text: $bankName)
                    TextField("卡种 (如: 运通白金)", text: $cardType)
                    TextField("尾号 (后四位)", text: $endNum)
                        .keyboardType(.numberPad)
                        .onChange(of: endNum) { oldValue, newValue in
                            if newValue.count > 4 { endNum = String(newValue.prefix(4)) }
                        }
                }
                
                HStack {
                    Text("还款日提醒 (每月)")
                    Spacer()
                    TextField("无", text: $repaymentDayStr)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                    Text("日")
                        .foregroundColor(.secondary)
                }

                Section(header: Text("奖励类型")) {
                    Picker("奖励类型", selection: $rewardType) {
                        ForEach(RewardType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                if rewardType == .points {
                    Section(header: Text("积分库")) {
                        if points.isEmpty {
                            Text("暂无积分库，请先创建")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Picker("选择积分计划", selection: $selectedPointID) {
                            Text("未选择").tag(UUID?.none)
                            ForEach(points) { point in
                                Text(point.displayName).tag(Optional(point.id))
                            }
                        }
                        Button("管理积分库") { showPointLibrary = true }
                    }
                }
                
                // 3. 颜色设置
                Section(header: Text("卡面风格")) {
                    ColorPicker("渐变色 1", selection: $color1)
                    ColorPicker("渐变色 2", selection: $color2)
                }
                
                Section(header: Text(capPeriodTitle)){
                    Picker(capPeriodTitle, selection: $capPeriod) {
                        Text("按月").tag(CapPeriod.monthly)
                        Text("按年").tag(CapPeriod.yearly)
                    }
                }
                .pickerStyle(.segmented)
                
                // 4. 规则设置 - 基础
                Section(header: Text(baseSectionTitle)) {
                    Picker("发行地区", selection: $region) {
                        ForEach(Region.allCases, id: \.self) { r in
                            Text("\(r.icon) \(r.rawValue)").tag(r)
                        }
                    }
                    
                    HStack {
                        Text(localRateTitle)
                        Spacer()
                        TextField("1.0", text: $defaultRateStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                    }
                    HStack {
                        Text(localCapTitle)
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        TextField("无上限", text: $localBaseCapStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text(foreignRateTitle)
                        Spacer()
                        TextField("同本币", text: $foreignRateStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                    }
                    HStack {
                        Text(foreignCapTitle)
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        TextField("无上限", text: $foreignBaseCapStr)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                
                // 5. 规则设置 - 类别
                Section(header: Text("类别加成 (额外叠加)")) {
                    CategoryInputRow(name: "餐饮", rate: $diningRateStr, cap: $diningCapStr, capUnit: rewardLabel)
                    CategoryInputRow(name: "超市", rate: $groceryRateStr, cap: $groceryCapStr, capUnit: rewardLabel)
                    CategoryInputRow(name: "出行", rate: $travelRateStr, cap: $travelCapStr, capUnit: rewardLabel)
                    CategoryInputRow(name: "数码", rate: $digitalRateStr, cap: $digitalCapStr, capUnit: rewardLabel)
                    CategoryInputRow(name: "其他", rate: $otherRateStr, cap: $otherCapStr, capUnit: rewardLabel)
                }
                
                // 6. 规则设置 - 支付方式
                Section(header: Text("支付方式规则 (可选)")) {
                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(method.displayName, systemImage: method.iconName)
                                    .foregroundColor(method.color)
                                Spacer()
                            }
                            
                            HStack {
                                Text("加成:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextField("0", value: rateBinding(for: method), format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 50)
                                    .padding(4)
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .cornerRadius(5)
                                Text("%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(rewardType == .points ? "积分上限:" : "上限:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextField("无", value: capBinding(for: method), format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                    .padding(4)
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .cornerRadius(5)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
            }
            .navigationTitle(cardToEdit == nil ? "添加信用卡" : "编辑卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveCard() }
                        .disabled(bankName.isEmpty || cardType.isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // 👇👇👇 核心修复：这里补上了监听器！
            // 1. 监听视图出现：如果有模版 URL 且没有图片，就开始下载
            .onAppear {
                if cardImageData == nil, let url = template?.pictureURL {
                    Task {
                        await imageManager.downloadImage(from: url)
                    }
                }
            }
            // 2. 监听下载完成，将图片转为 Data
            .onChange(of: imageManager.downloadedImage) { _, newImage in
                if let image = newImage {
                    self.cardImageData = image.jpegData(compressionQuality: 0.7)
                }
            }
            .onChange(of: rewardType) { _, newValue in
                if newValue != .points {
                    selectedPointID = nil
                }
            }
            .sheet(isPresented: $showPointLibrary) {
                PointLibraryView()
            }
        }
    }
    
    // MARK: - 辅助函数
    
    func rateBinding(for method: PaymentMethod) -> Binding<Double> {
        Binding(
            get: { self.paymentMethodRates[method] ?? 0.0 },
            set: { newValue in
                if newValue == 0 {
                    self.paymentMethodRates.removeValue(forKey: method)
                } else {
                    self.paymentMethodRates[method] = newValue
                }
            }
        )
    }
    
    func capBinding(for method: PaymentMethod) -> Binding<Double> {
        Binding(
            get: { self.paymentCaps[method] ?? 0.0 },
            set: { newValue in
                if newValue == 0 {
                    self.paymentCaps.removeValue(forKey: method)
                } else {
                    self.paymentCaps[method] = newValue
                }
            }
        )
    }
    
    // --- 核心保存逻辑 ---
    func saveCard() {
        let defaultRate = (Double(defaultRateStr) ?? 0) / 100.0
        let rDay = Int(repaymentDayStr) ?? 0
        var foreignRate: Double? = nil
        if !foreignRateStr.isEmpty {
            foreignRate = (Double(foreignRateStr) ?? 0) / 100.0
        }
        
        let c1Hex = color1.toHex() ?? "0000FF"
        let c2Hex = color2.toHex() ?? "000000"
        
        var specialRates: [Category: Double] = [:]
        if let rate = Double(diningRateStr), rate > 0 { specialRates[.dining] = rate / 100.0 }
        if let rate = Double(groceryRateStr), rate > 0 { specialRates[.grocery] = rate / 100.0 }
        if let rate = Double(travelRateStr), rate > 0 { specialRates[.travel] = rate / 100.0 }
        if let rate = Double(digitalRateStr), rate > 0 { specialRates[.digital] = rate / 100.0 }
        if let rate = Double(otherRateStr), rate > 0 { specialRates[.other] = rate / 100.0 }
        
        let locBaseCap = Double(localBaseCapStr) ?? 0
        let forBaseCap = Double(foreignBaseCapStr) ?? 0
        
        var catCaps: [Category: Double] = [:]
        if let cap = Double(diningCapStr), cap > 0 { catCaps[.dining] = cap }
        if let cap = Double(groceryCapStr), cap > 0 { catCaps[.grocery] = cap }
        if let cap = Double(travelCapStr), cap > 0 { catCaps[.travel] = cap }
        if let cap = Double(digitalCapStr), cap > 0 { catCaps[.digital] = cap }
        if let cap = Double(otherCapStr), cap > 0 { catCaps[.other] = cap }
        
        let finalPaymentRates = paymentMethodRates.mapValues { $0 / 100.0 }
        let finalPaymentCaps = paymentCaps
        let selectedPoint = points.first { $0.id == selectedPointID }
        let resolvedPointProgram = rewardType == .points ? selectedPoint : nil
        
        if let existingCard = cardToEdit {
            existingCard.bankName = bankName
            existingCard.type = cardType
            existingCard.endNum = endNum
            existingCard.colorHexes = [c1Hex, c2Hex]
            existingCard.defaultRate = defaultRate
            existingCard.issueRegion = region
            existingCard.foreignCurrencyRate = foreignRate
            existingCard.capPeriod = capPeriod
            existingCard.specialRates = specialRates
            
            existingCard.localBaseCap = locBaseCap
            existingCard.foreignBaseCap = forBaseCap
            existingCard.categoryCaps = catCaps
            existingCard.repaymentDay = rDay
            
            existingCard.paymentMethodRates = finalPaymentRates
            existingCard.paymentCaps = finalPaymentCaps
            existingCard.cardImageData = cardImageData
            existingCard.rewardType = rewardType
            existingCard.pointProgram = resolvedPointProgram
            
            NotificationManager.shared.scheduleNotification(for: existingCard)
            
        } else {
            let newCard = CreditCard(
                bankName: bankName,
                type: cardType,
                endNum: endNum,
                colorHexes: [c1Hex, c2Hex],
                defaultRate: defaultRate,
                specialRates: specialRates,
                issueRegion: region,
                foreignCurrencyRate: foreignRate,
                templateKey: template?.templateKey,
                
                localBaseCap: locBaseCap,
                foreignBaseCap: forBaseCap,
                categoryCaps: catCaps,
                capPeriod: capPeriod,
                repaymentDay: rDay,
                paymentMethodRates: finalPaymentRates,
                paymentCaps: finalPaymentCaps,
                rewardType: rewardType,
                pointProgram: resolvedPointProgram,
                cardImageData: cardImageData
            )
            context.insert(newCard)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationManager.shared.scheduleNotification(for: newCard)
            }
        }
        
        dismiss()
        onSaved?()
    }

    private var rewardLabel: String {
        rewardType == .points ? "积分" : "返现"
    }

    private var capPeriodTitle: String {
        rewardType == .points ? "积分上限周期" : "返现上限周期"
    }

    private var baseSectionTitle: String {
        rewardType == .points ? "基础积分 (所有消费)" : "基础返现 (所有消费)"
    }

    private var localRateTitle: String {
        rewardType == .points ? "本币积分率 (%)" : "本币返现率 (%)"
    }

    private var foreignRateTitle: String {
        rewardType == .points ? "外币积分率 (%)" : "外币返现率 (%)"
    }

    private var localCapTitle: String {
        if rewardType == .points {
            return capPeriod == .monthly ? "本币月积分上限" : "本币年积分上限"
        }
        return capPeriod == .monthly ? "本币月上限" : "本币年上限"
    }

    private var foreignCapTitle: String {
        if rewardType == .points {
            return capPeriod == .monthly ? "外币月积分上限" : "外币年积分上限"
        }
        return capPeriod == .monthly ? "外币月上限" : "外币年上限"
    }
    
    struct CategoryInputRow: View {
        let name: String
        @Binding var rate: String
        @Binding var cap: String
        let capUnit: String
        
        var body: some View {
            VStack(spacing: 8) {
                HStack {
                    Text(name)
                        .fontWeight(.medium)
                    Spacer()
                    Text("加成%")
                        .font(.caption).foregroundColor(.gray)
                    TextField("0", text: $rate)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 40)
                        .padding(5)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(5)
                    
                    Text(capUnit == "积分" ? "积分上限" : "上限")
                        .font(.caption).foregroundColor(.gray)
                    TextField("无", text: $cap)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .padding(5)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(5)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
