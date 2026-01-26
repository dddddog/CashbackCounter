import SwiftUI
import SwiftData

// --- 定义弹窗枚举，用于状态管理 ---
enum SheetType: Identifiable {
    case templateList
    case addCard
    case editCard(CreditCard)
    
    var id: String {
        switch self {
        case .templateList: return "templateList"
        case .addCard: return "addCard"
        case .editCard(let card): return "editCard-\(card.id)"
        }
    }
}

struct CardListView: View {
    @Environment(\.modelContext) var context
    
    // 1. 数据查询：View 负责观察数据变化
    @Query(sort: [SortDescriptor(\CreditCard.bankName, order: .forward)])
    var dbCards: [CreditCard]
    
    // 2. ViewModel 驱动逻辑
    @State private var viewModel: CardListViewModel
    
    // 3. 初始化：接收从顶层传来的 Repository
    init(repository: TransactionRepositoryProtocol) {
        self._viewModel = State(initialValue: CardListViewModel(repository: repository))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        if dbCards.isEmpty {
                            emptyStateView
                        } else {
                            cardListContent
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("我的卡包")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.activeSheet = .templateList
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            // --- 统一弹窗管理器 ---
            .sheet(item: $viewModel.activeSheet) { sheet in
                switch sheet {
                case .templateList:
                    CardTemplateListView(
                        repository: viewModel.repository,
                        rootSheet: $viewModel.activeSheet
                    )
                case .addCard:
                    AddCardView(repository: viewModel.repository)
                case .editCard(let card):
                    AddCardView(repository: viewModel.repository, cardToEdit: card)
                }
            }
            // --- 删除确认弹窗 ---
            .alert("确认删除", isPresented: $viewModel.showDeleteAlert) {
                Button("删除", role: .destructive) { viewModel.confirmDelete() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("确定要删除这张卡片吗？删除后，该卡关联的交易记录将不再显示所属卡片，且自动提醒将被取消。")
            }
        }
    }
}

// MARK: - UI 子组件
extension CardListView {
    
    /// 卡片列表渲染
    private var cardListContent: some View {
        ForEach(dbCards) { card in
            NavigationLink(destination: CardDetailView(card: card)) {
                CreditCardView(
                    bankName: card.bankName,
                    type: card.type,
                    endNum: card.endNum,
                    colors: card.colors
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    viewModel.activeSheet = .editCard(card)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    viewModel.prepareDelete(card)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
    
    /// 空状态视图
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("暂无卡片", systemImage: "creditcard")
        } description: {
            Text("点击右上角加号，从模板或自定义添加你的第一张信用卡")
        }
    }
}
