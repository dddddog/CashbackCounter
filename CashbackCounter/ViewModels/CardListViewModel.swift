// CardListViewModel.swift
import SwiftUI
import SwiftData

@Observable
class CardListViewModel {
    // --- 1. 弹窗与交互状态 ---
    var activeSheet: SheetType?
    var showDeleteAlert = false
    
    var cardToEdit: CreditCard?
    var cardToDelete: CreditCard?
    var selectedTemplate: CardTemplate?

    // --- 2. 核心引用 ---
    // 建议之后将 TransactionRepository 扩展为支持 Card，或者新建 CardRepository
    let repository: TransactionRepositoryProtocol

    init(repository: TransactionRepositoryProtocol) {
        self.repository = repository
    }

    // --- 3. 业务逻辑 ---
    
    /// 准备编辑卡片
    func prepareEdit(_ card: CreditCard) {
        self.cardToEdit = card
    }
    
    /// 准备删除卡片
    func prepareDelete(_ card: CreditCard) {
        self.cardToDelete = card
        self.showDeleteAlert = true
    }

    /// 执行删除
    func confirmDelete() {
        if let card = cardToDelete {
            // 注意：这里需要 Repository 支持删除卡片
            // 暂时可以先用 context 直接处理，但长远看应移入 Repository
            repository.deleteCard(card)
            try? repository.save()
            self.cardToDelete = nil
        }
    }
}
