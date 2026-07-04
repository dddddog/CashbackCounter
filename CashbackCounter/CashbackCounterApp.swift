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

    init() {
        NotificationManager.shared.requestAuthorization()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
            .preferredColorScheme(userTheme == 1 ? .light : (userTheme == 2 ? .dark : nil))
            .environment(\.locale, userLanguage == "system" ? .current : Locale(identifier: userLanguage))
            .environmentObject(aiAvailability)
            .task {
                aiAvailability.refreshSupportStatus()
            }
        }
        .modelContainer(for: [Transaction.self, CreditCard.self, CardTemplate.self, Income.self, Point.self, PointAdjustment.self])
        
    }
}
