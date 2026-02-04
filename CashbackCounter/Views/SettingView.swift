//
//  SettingsView.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/29/25.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Helper Models
// 1. 新增：用于封装分享数据的结构体，遵循 Identifiable 协议
// 这解决了 .sheet(isPresented:) 导致的时序问题
struct ShareData: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct SettingsView: View {
    // MARK: - Properties
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    
    @AppStorage("userTheme") private var userTheme: Int = 0
    @AppStorage("userLanguage") private var userLanguage: String = "system"
    @AppStorage("mainCurrencyCode") private var mainCurrencyCode: String = "CNY"
    
    @Environment(\.modelContext) var context
    @State private var showConfirmClear: Bool = false
    
    // 获取数据库数据
    @Query var cards: [CreditCard]
    @Query(
        sort: [
            SortDescriptor(\Transaction.date, order: .reverse),
            SortDescriptor(\Transaction.merchant, order: .forward)
        ]
    )
    var transactions: [Transaction]
    
    // MARK: - Export State
    // 2. 修改：使用 item 形式的状态来控制 Sheet
    @State private var shareData: ShareData?
    // 3. 新增：控制导出过程中的 Loading 状态
    @State private var isExporting = false

    // MARK: - Body
    var body: some View {
        NavigationView {
            List {
                // Header Section
                Section {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                                .offset(x: -5, y: 0)
                            
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                                .padding(4)
                                .background(Color(uiColor: .systemGroupedBackground).clipShape(Circle()))
                                .offset(x: 18, y: 12)
                        }
                        .padding(.bottom, 4)
                        
                        Text("Cashback Counter")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .listRowBackground(Color.clear)
                
                // Appearance Section
                Section(header: Text("外观与语言")) {
                    Picker(selection: $userTheme, label: Label("主题模式", systemImage: "paintpalette")) {
                        Text("跟随系统").tag(0)
                        Text("浅色模式").tag(1)
                        Text("深色模式").tag(2)
                    }
                    
                    Picker(selection: $userLanguage, label: Label("语言设置", systemImage: "globe")) {
                        Text("跟随系统").tag("system")
                        Text("简体中文").tag("zh-Hans")
                        Text("繁體中文").tag("zh-Hant")
                        Text("English").tag("en")
                    }
                }
                
                // General Section
                Section(header: Text("常规")) {
                    Picker(selection: $mainCurrencyCode, label: Label("主货币", systemImage: "banknote")) {
                        Text("人民币 (CNY)").tag("CNY")
                        Text("美元 (USD)").tag("USD")
                        Text("港币 (HKD)").tag("HKD")
                        Text("日元 (JPY)").tag("JPY")
                    }
                    
                    NavigationLink(destination: NotificationSettingsView()) {
                        Label("通知提醒", systemImage: "bell")
                    }
                }
                
                // Data Management Section
                Section(header: Text("数据管理")) {
                    Label("iCloud 同步 (功能正在开发中)", systemImage: "icloud")
                        .foregroundColor(.secondary)
                    
                    Button {
                        startExportProcess()
                    } label: {
                        HStack {
                            Label("全部数据导出", systemImage: "square.and.arrow.up")
                            Spacer()
                            
                            if isExporting {
                                ProgressView()
                                    .padding(.leading, 5)
                            } else {
                                Text("导出卡片与账单")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .disabled(isExporting) // 导出过程中禁止重复点击
                }
                
                // About Section
                Section(header: Text("关于 Cashback Counter")) {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text("v\(appVersion)")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink(destination: DeveloperView()) {
                        Label("开发者/贡献者", systemImage: "person.crop.circle")
                    }
                }
                
                // Reset Section
                Section {
                    Button(role: .destructive) {
                        showConfirmClear = true
                    } label: {
                        Label("重置所有数据 (慎用)", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .confirmationDialog(
                        "确定要清除所有数据吗？",
                        isPresented: $showConfirmClear,
                        titleVisibility: .visible
                    ) {
                        Button("清除", role: .destructive) {
                            clearAllData()
                        }
                        Button("取消", role: .cancel) {}
                    }
                }
            }
            .navigationTitle("设置")
            .listStyle(.insetGrouped)
            // 4. 关键修复：使用 item: $shareData 绑定
            // 只有当 shareData 有值时，才会初始化并显示 ActivityViewController
            .sheet(item: $shareData) { data in
                ActivityViewController(activityItems: data.items)
                    .presentationDetents([.medium, .large])
            }
        }
    }
    
    // MARK: - Logic Methods
    
    /// 开始异步导出流程
    private func startExportProcess() {
        // 1. 开启 Loading 状态
        isExporting = true
        
        Task {
            // 2. 稍微延迟一点点 (0.2秒)，让 UI 有机会刷新出 ProgressView
            // 否则在主线程做繁重工作会直接卡住 UI，连转圈都看不到
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            // 3. 执行导出数据生成 (耗时操作)
            let items = generateExportItems()
            
            // 4. 完成后更新 UI 状态
            // Task 在 SwiftUI View 中默认运行在 MainActor，所以可以直接更新 State
            isExporting = false
            
            if !items.isEmpty {
                // 赋值给 shareData，自动触发 .sheet(item: ...)
                self.shareData = ShareData(items: items)
            }
        }
    }
    
    /// 生成导出文件 (CSV + ZIP)
    private func generateExportItems() -> [Any] {
        var items: [Any] = []
        
        // A. 导出卡片 CSV
        if let cardCSV = cards.exportCSVFile() {
            items.append(cardCSV)
        }
        
        // B. 导出账单+收据 ZIP
        if let backupZip = transactions.exportReceiptsZip() {
            items.append(backupZip)
        }
        
        return items
    }
    
    private func clearAllData() {
        do {
            try deleteAll(of: Transaction.self)
            try deleteAll(of: CreditCard.self)
            try context.save()
            print("✅ All data cleared")
        } catch {
            print("❌ Failed to clear data: \(error)")
        }
    }

    private func deleteAll<T>(of type: T.Type) throws where T: SwiftData.PersistentModel {
        let descriptor = SwiftData.FetchDescriptor<T>()
        let items = try context.fetch(descriptor)
        for item in items {
            context.delete(item)
        }
    }
}

// MARK: - ActivityViewController
struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
