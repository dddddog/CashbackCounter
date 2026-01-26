// TrendAnalysisView.swift
import SwiftUI
import Charts

struct TrendAnalysisView: View {
    @Environment(\.dismiss) var dismiss
    @State private var viewModel: TrendAnalysisViewModel

    init(transactions: [Transaction], exchangeRates: [String: Double], type: TrendAnalysisViewModel.TrendType) {
        self._viewModel = State(initialValue: TrendAnalysisViewModel(
            transactions: transactions,
            exchangeRates: exchangeRates,
            type: type
        ))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 25) {
                    // 1. 总额概览
                    summaryHeader
                    
                    // 2. 时间范围选择
                    Picker("时间范围", selection: $viewModel.selectedTimeframe) {
                        ForEach(TrendAnalysisViewModel.Timeframe.allCases, id: \.self) { frame in
                            Text(frame.rawValue).tag(frame)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // 3. 图表展示
                    chartContainer
                    
                    // 4. 数据详情列表
                    detailsList
                }
                .padding(.vertical)
            }
            .navigationTitle(viewModel.type == .expense ? "支出趋势" : "返现趋势")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 子组件
extension TrendAnalysisView {
    private var summaryHeader: some View {
        VStack(spacing: 8) {
            Text("统计时段总额")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(String(format: "%.2f", viewModel.totalAmount))
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
        }
    }

    private var chartContainer: some View {
            // 1. 定义基础颜色和渐变色
            let baseColor = viewModel.type == .expense ? Color.red : Color.green
            let gradientColor = LinearGradient(
                gradient: Gradient(colors: [baseColor.opacity(0.4), baseColor.opacity(0.05)]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // 确定 X 轴单位 (沿用之前的修复逻辑)
            let xAxisUnit: Calendar.Component = (viewModel.selectedTimeframe == .sevenDays || viewModel.selectedTimeframe == .oneMonth) ? .day : .month

            return Chart {
                ForEach(viewModel.chartData) { point in
                    // 2. 底层：阴影区域 (AreaMark)
                    AreaMark(
                        x: .value("日期", point.date, unit: xAxisUnit),
                        y: .value("金额", point.amount)
                    )
                    .foregroundStyle(gradientColor)
                    .interpolationMethod(.catmullRom) // 设置为平滑曲线

                    // 3. 顶层：折线 (LineMark)
                    LineMark(
                        x: .value("日期", point.date, unit: xAxisUnit),
                        y: .value("金额", point.amount)
                    )
                    .foregroundStyle(baseColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)) // 加粗线条
                    .interpolationMethod(.catmullRom) // 同样设置为平滑曲线
                    
                    // 可选：给数据点加个小圆点，让它更清晰
                    PointMark(
                         x: .value("日期", point.date, unit: xAxisUnit),
                         y: .value("金额", point.amount)
                    )
                    .foregroundStyle(baseColor)
                    .symbolSize(30) // 点的大小
                }
            }
            .frame(height: 280) // 稍微调高一点高度
            .padding(.horizontal)
            // 4. Y轴优化：不强制包含0，让波动看起更明显
            .chartYScale(domain: .automatic(includesZero: false))
            // 5. X轴配置 (保持之前的修复)
            .chartXAxis {
                if viewModel.selectedTimeframe == .sevenDays || viewModel.selectedTimeframe == .oneMonth {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        if viewModel.selectedTimeframe == .sevenDays { AxisGridLine() } // 7天显示网格
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month().day(), centered: true)
                    }
                } else {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisGridLine()
                        AxisTick()
                        // 优化：只显示简短的月份，如果是年初则显示年份
                        if let date = value.as(Date.self) {
                            let month = Calendar.current.component(.month, from: date)
                            AxisValueLabel {
                                Text(month == 1 ? date.formatted(.dateTime.year()) : date.formatted(.dateTime.month()))
                            }
                        }
                    }
                }
            }
            // 6. Y轴配置：隐藏轴线，只显示网格和数字，更简洁
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
        }
    
    private var detailsList: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("历史记录").font(.headline).padding(.horizontal)
            
            ForEach(viewModel.chartData.reversed()) { point in
                HStack {
                    Text(point.date, format: .dateTime.year().month().day())
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f", point.amount))
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
}
