//
//  TransactionDetailView.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/25/25.
//

import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var transaction: Transaction
    
    @State private var showEditSheet = false
    @State private var showFullScreenReceipt = false
    
    // 格式化日期
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - 1. 顶部 Header (商户 & 金额)
                Section {
                    VStack(spacing: 16) {
                        // 商户/分类图标
                        ZStack {
                            Circle()
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                .frame(width: 80, height: 80)
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                            
                            Image(systemName: transaction.category.iconName)
                                .font(.system(size: 36))
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 10)
                        
                        VStack(spacing: 4) {
                            Text(transaction.merchant)
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            // 金额显示
                            Text(String(format: "%.2f", transaction.amount))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            // 币种
                            Text(transaction.location.currencyCode)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .cornerRadius(4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear) // 透明背景
                    .listRowInsets(EdgeInsets())    // 移除边距
                    .padding(.bottom, 10)
                }
                
                // MARK: - 2. 交易信息
                Section("基本信息") {
                    DetailRow(title: "交易时间", value: dateFormatter.string(from: transaction.date), icon: "calendar")
                    
                    DetailRow(title: "消费类别", value: transaction.category.displayName, icon: "tag")
                    
                    DetailRow(title: "消费地区", value: transaction.location.rawValue, icon: "mappin.and.ellipse")
                }
                
                // MARK: - 3. 支付详情 (包含新增的支付方式)
                Section("支付详情") {
                    // 👇 新增：支付方式
                    HStack {
                        Label {
                            Text("支付方式")
                        } icon: {
                            Image(systemName: "iphone.gen3") // 通用支付图标，或用 link
                                .foregroundColor(.purple)
                        }
                        
                        Spacer()
                        
                        // 支付方式的具体内容
                        HStack(spacing: 6) {
                            Image(systemName: transaction.paymentMethod.iconName)
                                .foregroundColor(transaction.paymentMethod.color)
                            Text(transaction.paymentMethod.displayName)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(transaction.paymentMethod.color.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // 支付卡片
                    if let card = transaction.card {
                        HStack {
                            Label("支付卡片", systemImage: "creditcard")
                            Spacer()
                            HStack(spacing: 6) {
                                // 卡片颜色小圆点
                                Circle()
                                    .fill(LinearGradient(
                                        colors: card.colors, // 👈 直接使用 [Color] 数组
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 12, height: 12)
                                
                                Text("\(card.bankName) \(card.type)")
                                    .foregroundColor(.secondary)
                                Text("(\(card.endNum))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    } else {
                        DetailRow(title: "支付卡片", value: "无卡/现金", icon: "creditcard")
                    }
                    
                    // 入账金额 (如果有汇率差)
                    HStack {
                        Label("入账金额", systemImage: "banknote")
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(String(format: "%.2f %@", transaction.billingAmount, transaction.card?.issueRegion.currencyCode ?? "CNY"))
                            // 如果原币种和入账币种不同，显示汇率
                            if transaction.amount != transaction.billingAmount && transaction.amount > 0 {
                                let rate = transaction.billingAmount / transaction.amount
                                Text("汇率约 \(String(format: "%.4f", rate))")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                // MARK: - 4. 返现分析
                Section("返现分析") {
                    HStack {
                        Label {
                            Text("预计返现")
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                        }
                        Spacer()
                        Text("+\(String(format: "%.2f", transaction.cashbackamount))")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    
                    // 计算出的实际回馈率
                    if transaction.billingAmount > 0 {
                        let actualRate = (transaction.cashbackamount / transaction.billingAmount) * 100
                        DetailRow(title: "实际回馈率", value: String(format: "%.2f%%", actualRate), icon: "percent")
                    }
                }
                
                // MARK: - 5. 凭证与关联
                Section("凭证") {
                    if let data = transaction.receiptData, let uiImage = UIImage(data: data) {
                        Button {
                            showFullScreenReceipt = true
                        } label: {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .listRowInsets(EdgeInsets())
                        }
                    } else {
                        HStack {
                            Image(systemName: "doc.text.image")
                                .foregroundColor(.gray)
                            Text("无收据图片")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // 显示关联的收入 (如果有)
                if let incomes = transaction.incomes, !incomes.isEmpty {
                    Section("已抵扣/关联收入") {
                        ForEach(incomes) { income in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(income.platform)
                                        .font(.subheadline)
                                    Text(income.dateString)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Text("-\(String(format: "%.2f", income.amount))")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                // 删除按钮
                Section {
                    Button(role: .destructive) {
                        dismiss()
                        // 稍微延迟删除，防止动画冲突
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            transaction.modelContext?.delete(transaction)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("删除此交易")
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped) // 更加现代的圆角分组风格
            .navigationTitle("交易详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑") {
                        showEditSheet = true
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                AddTransactionView(transaction: transaction)
            }
            // 简单的全屏查看收据
            .fullScreenCover(isPresented: $showFullScreenReceipt) {
                if let data = transaction.receiptData, let img = UIImage(data: data) {
                    ReceiptFullScreenView(image: img)
                }
            }
        }
    }
}

// 辅助视图：通用的详情行
struct DetailRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}


