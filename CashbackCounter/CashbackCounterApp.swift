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
        
        do {
            let schema = Schema([
                Transaction.self, CreditCard.self, Income.self, Point.self, PointAdjustment.self
            ])
            #if targetEnvironment(simulator)
            // 在模拟器中，如果未登录 iCloud 或 CloudKit 容器未配置好，频繁的同步重试会导致控制台无限输出 Zone Not Found 错误，从而引发主线程严重卡顿。
            // 故在模拟器环境下默认不启用 CloudKit 同步，保证开发调试时的流畅度。
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: nil)
            #else
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            #endif
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to configure SwiftData container with CloudKit: \(error)")
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
