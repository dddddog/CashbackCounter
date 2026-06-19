import AppIntents

struct CashbackShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionFromSMSIntent(),
            phrases: [
                "新增短信账单到 \(.applicationName)",
                "使用 \(.applicationName) 解析信用卡短信",
                "快捷添加短信消费到 \(.applicationName)"
            ],
            shortTitle: "解析信用卡短信",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: AddTransactionFromScreenshotIntent(),
            phrases: [
                "截屏记账到 \(.applicationName)",
                "使用 \(.applicationName) 识别截图账单",
                "快捷截图记账到 \(.applicationName)"
            ],
            shortTitle: "截屏智能记账",
            systemImageName: "camera.viewfinder"
        )
    }
}

