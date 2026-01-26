import SwiftUI
import SwiftData

// --- 1. 修复：定义 SheetType ---
// 这个枚举用于控制父视图 CardListView 的弹窗逻辑

struct CardTemplateListView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    
    // --- 2. 注入 Repository ---
    let repository: TransactionRepositoryProtocol
    
    @Query(sort: [
        SortDescriptor<CardTemplate>(\.bankName),
        SortDescriptor<CardTemplate>(\.type)
    ]) private var templates: [CardTemplate]

    @State private var selectedTemplate: CardTemplate?
    @Binding var rootSheet: SheetType?

    var body: some View {
        NavigationView {
            List(templates) { item in
                Button(action: {
                    selectedTemplate = item
                }) {
                    HStack {
                        // 预览颜色
                        Circle()
                            .fill(LinearGradient(
                                colors: item.colors.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 40, height: 40)

                        VStack(alignment: .leading) {
                            Text(item.bankName).font(.headline)
                            Text(item.type).font(.caption).foregroundColor(.gray)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("选择卡片模板")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            // --- 3. 核心跳转：弹出 AddCardView ---
            .sheet(item: $selectedTemplate) { template in
                // ✅ 这里必须传入 repository
                AddCardView(repository: repository, template: template, onSaved: {
                    // 当添加页保存成功时，关闭所有层级的弹窗
                    rootSheet = nil
                })
            }
        }
    }
}
