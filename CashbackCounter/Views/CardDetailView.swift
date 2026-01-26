// CardDetailView.swift
import SwiftUI
import SwiftData

struct CardDetailView: View {
    @Environment(\.dismiss) var dismiss
    
    // 1. 使用 ViewModel 管理状态
    @State private var viewModel: CardDetailViewModel
    
    // 2. 初始化：通过传参初始化 ViewModel
    init(card: CreditCard) {
        self._viewModel = State(initialValue: CardDetailViewModel(card: card))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // --- 1. 顶部卡片大图 ---
                        VStack {
                            CreditCardView(
                                bankName: viewModel.card.bankName,
                                type: viewModel.card.type,
                                endNum: viewModel.card.endNum,
                                colors: viewModel.card.colors
                            )
                            .frame(height: 220)
                            .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 5)
                        }
                        .padding(.top, 20)
                        
                        // --- 2. 交易列表区域 ---
                        VStack(alignment: .leading, spacing: 0) {
                            Text("最新交易")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)
                                .padding(.bottom, 8)
                            
                            if viewModel.sortedTransactions.isEmpty {
                                emptyStateView
                            } else {
                                transactionListView
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(viewModel.card.bankName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
            }
        }
    }
}

// MARK: - UI 子组件 (ViewBuilders)
extension CardDetailView {
    
    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.4))
            Text("此卡片暂无交易记录")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    /// 交易列表组件
    private var transactionListView: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.sortedTransactions) { transaction in
                VStack(spacing: 0) {
                    // 💡 如果你之前在 BillHomeView 重构中给 TransactionRow 增加了 exchangeRates
                    // 可以在 ViewModel 里也传入汇率，或者在这里保持简洁
                    TransactionRow(transaction: transaction)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                    
                    if transaction != viewModel.sortedTransactions.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}
