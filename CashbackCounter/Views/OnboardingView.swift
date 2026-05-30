import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selection = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "欢迎使用Cashback Counter",
            message: "你的智能返现计算助手，轻松管理你的消费。",
            systemImage: "creditcard",
            accentColor: Color(red: 0.10, green: 0.55, blue: 0.95)
        ),
        OnboardingPage(
            title: "拍一笔，快速记账",
            message: "拍照或手动输入，快速记录每一笔消费。",
            systemImage: "camera.viewfinder",
            accentColor: Color(red: 0.10, green: 0.55, blue: 0.95)
        ),
        OnboardingPage(
            title: "卡包管理",
            message: "添加信用卡，配置返现/积分规则，随时查看卡片详情。",
            systemImage: "creditcard",
            accentColor: Color(red: 0.15, green: 0.70, blue: 0.55)
        ),
        OnboardingPage(
            title: "导入账单与结单识别",
            message: "导入 CSV 或 ZIP 备份，上传结单 PDF 自动对账。",
            systemImage: "doc.text.magnifyingglass",
            accentColor: Color(red: 0.95, green: 0.55, blue: 0.20)
        ),
        OnboardingPage(
            title: "趋势与积分",
            message: "查看支出趋势与积分进度，让消费更有方向。",
            systemImage: "chart.line.uptrend.xyaxis",
            accentColor: Color(red: 0.45, green: 0.35, blue: 0.90)
        ),
        OnboardingPage(
            title: "更新须知",
            message: "建议在更新版本前，提前在设置页将全部数据导出并保存，以免出现问题",
            systemImage: "exclamationmark.triangle",
            accentColor: Color(red: 0.45, green: 0.35, blue: 0.90)
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.08, green: 0.10, blue: 0.14), Color(red: 0.10, green: 0.12, blue: 0.13)]
                    : [Color(red: 0.93, green: 0.97, blue: 1.0), Color(red: 0.92, green: 0.95, blue: 0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button("跳过") {
                        onFinish()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                            .padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(action: advance) {
                    Text(selection == pages.count - 1 ? "开始使用" : "继续")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private func advance() {
        if selection < pages.count - 1 {
            withAnimation(.easeInOut) {
                selection += 1
            }
        } else {
            onFinish()
        }
    }
}

private struct OnboardingPage {
    let title: String
    let message: String
    let systemImage: String
    let accentColor: Color
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(page.accentColor.opacity(0.15))
                    .frame(width: 160, height: 160)

                Image(systemName: page.systemImage)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundColor(page.accentColor)
            }

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(page.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)

            Spacer()
        }
        .padding(.top, 20)
    }
}
