import SwiftUI
import SwiftData

// --- 2. 主入口 (包含底部导航栏) ---
struct ContentView: View {
    // 选中的 Tab 索引
    @State private var selectedTab = 0
    @Environment(\.modelContext) var context
    var body: some View {
        let repo = TransactionRepository(context: context)
        // TabView 是底部导航栏的核心容器
        TabView(selection: $selectedTab) {
            
            // --- 左边：账单页 ---
            BillHomeView(repository: repo)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "doc.text.image.fill" : "doc.text.image")
                    Text("账单")
                }
                .tag(0)
            
            // --- 中间：拍照/记账页 ---
            CameraRecordView(repository: repo)
                .tabItem {
                    Image(systemName: "camera.circle.fill") // 大圆圈图标
                    Text("拍一笔")
                }
                .tag(1)
            
            // --- 右边：信用卡页 ---
            CardListView(repository: repo) // ✅ 传入创建好的 repo
                .tabItem {
                    Label("卡包", systemImage: selectedTab == 2 ? "creditcard.fill" : "creditcard")
                }
                .tag(2)
            
            // --- ✨ 新增：设置页 ---
            SettingsView()
                .tabItem {
                    // 选中时变成实心齿轮
                    Image(systemName: selectedTab == 3 ? "gearshape.fill" : "gearshape")
                    Text("设置")
                }
                .tag(3)
        }
        .tint(.blue) // 设置底部选中时的颜色 (Apple 蓝)
    }
}
