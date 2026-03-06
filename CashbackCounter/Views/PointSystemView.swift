import SwiftUI
import SwiftData

struct PointSystemView: View {
    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var transactions: [Transaction]

    var body: some View {
        let summaries = pointSummaries
        let totalPoints = summaries.reduce(0) { $0 + $1.points }

        return NavigationView {
            List {
                Section {
                    StatBox(
                        title: "当前积分",
                        amount: "\(formattedPoints(totalPoints)) 积分",
                        icon: "star.circle.fill",
                        color: .yellow
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section(header: Text("积分明细")) {
                    if summaries.isEmpty {
                        ContentUnavailableView(
                            "暂无积分记录",
                            systemImage: "star.circle",
                            description: Text("新增积分返现交易后，这里会显示累计积分")
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(summaries) { summary in
                            HStack {
                                Text(summary.title)
                                    .font(.headline)
                                Spacer()
                                Text("\(formattedPoints(summary.points)) 积分")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("积分系统")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var pointSummaries: [PointSummary] {
        var totals: [String: Int] = [:]
        var titles: [String: String] = [:]

        for transaction in transactions {
            let earned = max(0, transaction.pointsEarned)
            guard earned > 0 else { continue }

            if let program = transaction.card?.pointProgram {
                let key = program.id.uuidString
                totals[key, default: 0] += earned
                titles[key] = program.displayName
            } else {
                let key = "unassigned"
                totals[key, default: 0] += earned
                titles[key] = "未分配积分计划"
            }
        }

        return totals.map { key, points in
            PointSummary(id: key, title: titles[key] ?? "积分", points: points)
        }
        .sorted { $0.title < $1.title }
    }

    private func formattedPoints(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private struct PointSummary: Identifiable {
    let id: String
    let title: String
    let points: Int
}
