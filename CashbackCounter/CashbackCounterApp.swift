//
//  CashbackCounterApp.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/23/25.
//

import SwiftUI
import SwiftData

@main // 👈 1. 这里的 @main 就相当于 Java 的 public static void main()。
      // 它告诉系统：程序从这里开始跑！
struct CashbackCounterApp: App { // 2. 这个结构体必须遵守 App 协议
    @AppStorage("userTheme") private var userTheme: Int = 0
    @AppStorage("userLanguage") private var userLanguage: String = "system"
    
    let container: ModelContainer
    
    init() {
        NotificationManager.shared.requestAuthorization()
        
        let schema = Schema([
            Transaction.self, CreditCard.self, Income.self, Point.self, PointAdjustment.self
        ])
        let isSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
        
        #if targetEnvironment(simulator)
        // 在模拟器中，如果未登录 iCloud 或 CloudKit 容器未配置好，频繁的同步重试会导致控制台无限输出 Zone Not Found 错误，从而引发主线程严重卡顿。
        // 故在模拟器环境下默认不启用 CloudKit 同步，保证开发调试时的流畅度。
        let cloudKitDB: ModelConfiguration.CloudKitDatabase = .none
        #else
        let cloudKitDB: ModelConfiguration.CloudKitDatabase = isSyncEnabled ? .automatic : .none
        #endif
        
        // 第一次尝试正常创建
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: cloudKitDB)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema 迁移失败（常见于 CloudKit 同步后字段变更），尝试删除本地数据库后重建
            print("⚠️ ModelContainer 初始化失败，尝试删除本地数据库并重建... 错误: \(error)")
            
            // 删除本地 SwiftData 存储文件
            let defaultURL = URL.applicationSupportDirectory.appending(path: "default.store")
            let filesToDelete = [
                defaultURL,
                defaultURL.appendingPathExtension("shm"),
                defaultURL.appendingPathExtension("wal")
            ]
            for url in filesToDelete {
                try? FileManager.default.removeItem(at: url)
            }
            
            // 第二次尝试：使用全新的空数据库
            do {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: cloudKitDB)
                container = try ModelContainer(for: schema, configurations: [config])
                print("✅ 已成功重建本地数据库，iCloud 数据将自动重新同步。")
            } catch {
                // 最终兜底：使用内存模式，至少不崩溃
                print("❌ 重建数据库也失败了，回退到内存模式: \(error)")
                do {
                    let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                    container = try ModelContainer(for: schema, configurations: [memConfig])
                } catch {
                    fatalError("无法创建任何 ModelContainer: \(error)")
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(CardTemplateManager.shared)
                .preferredColorScheme(userTheme == 1 ? .light : (userTheme == 2 ? .dark : nil))
                .environment(\.locale, userLanguage == "system" ? .current : Locale(identifier: userLanguage))
        }
        .modelContainer(container)
        
    }
}
