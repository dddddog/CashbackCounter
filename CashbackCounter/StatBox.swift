// StatBox.swift
import SwiftUI

struct StatBox: View {
    let title: String
    let amount: String
    let icon: String
    let color: Color
    var isLoading: Bool = false // 新增加载状态

    var body: some View {
        HStack(spacing: 12) {
            // 图标部分
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                if isLoading {
                    // 骨架屏效果
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 20)
                        .shimmer() // 自定义闪烁动画
                } else {
                    Text(amount)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .minimumScaleFactor(0.8) // 防止金额过长溢出
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

// 简单的闪烁动画效果
extension View {
    @ViewBuilder
    func shimmer() -> some View {
        self.modifier(ShimmerEffect())
    }
}

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.5), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + (geo.size.width * 2 * phase))
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
