//
//  DesignConstants.swift
//  CashbackCounter
//
//  统一设计常量系统 — 用于替代散落在各视图中的魔法数字。
//  使用动态值适配不同屏幕尺寸的 iPhone (SE ~ Pro Max)。
//

import SwiftUI

enum DesignConstants {

    // MARK: - 屏幕宽度（统一获取入口，兼容 iOS 26 弃用 UIScreen.main）

    /// 获取当前活跃窗口场景的屏幕宽度
    private static var screenWidth: CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            return windowScene.screen.bounds.width
        }
        return 375 // fallback 默认值（iPhone SE 宽度）
    }

    /// 是否为小屏设备（iPhone SE 等 375pt 以下）
    static var isCompact: Bool { screenWidth < 375 }

    // MARK: - 圆角半径

    enum CornerRadius {
        /// 小元素：标签、badge、小按钮 (5pt)
        static let small: CGFloat = 5
        /// 中等元素：筛选器按钮、输入框 (8pt)
        static let medium: CGFloat = 8
        /// 大元素：卡片容器、弹窗 (12pt)
        static let large: CGFloat = 12
        /// 特大元素：趋势图卡片 (16pt)
        static let extraLarge: CGFloat = 16
        /// 药丸形状：积分卡片 (18pt)
        static let pill: CGFloat = 18
    }

    // MARK: - 间距 (动态适配不同屏幕宽度)

    enum Spacing {
        /// 水平边距 — 小屏 12pt，大屏 16pt
        static var horizontalPadding: CGFloat { DesignConstants.isCompact ? 12 : 16 }

        /// 列表项之间的间距
        static var listItemSpacing: CGFloat { DesignConstants.isCompact ? 10 : 15 }

        /// Section 之间的间距
        static var sectionSpacing: CGFloat { DesignConstants.isCompact ? 15 : 20 }

        /// 统计栏内部元素间距
        static var statsSpacing: CGFloat { DesignConstants.isCompact ? 10 : 15 }

        /// 筛选器 chip 之间的间距
        static let chipSpacing: CGFloat = 10

        /// 筛选器两侧留白
        static let chipEdgeInset: CGFloat = 16

        /// 底部按钮区域的底边距
        static var bottomPadding: CGFloat { DesignConstants.isCompact ? 40 : 50 }

        /// 底部按钮区域的水平边距
        static var bottomHorizontalPadding: CGFloat { DesignConstants.isCompact ? 24 : 30 }
    }

    // MARK: - 尺寸 (动态适配)

    enum Size {
        /// 卡面图片容器高度
        static var cardImageHeight: CGFloat { DesignConstants.isCompact ? 180 : 200 }

        /// 设置页 App 图标圆圈
        static var settingsIconCircle: CGFloat { DesignConstants.isCompact ? 70 : 80 }
        static var settingsIconFont: CGFloat { DesignConstants.isCompact ? 36 : 40 }

        /// 相机拍照按钮（外圈）
        static var cameraButtonOuter: CGFloat { DesignConstants.isCompact ? 60 : 70 }
        /// 相机拍照按钮（内圈）
        static var cameraButtonInner: CGFloat { DesignConstants.isCompact ? 50 : 60 }
        /// 相机两侧按钮
        static var cameraSideButton: CGFloat { DesignConstants.isCompact ? 50 : 60 }

        /// 拖拽提示图标
        static var dropIndicatorIcon: CGFloat { DesignConstants.isCompact ? 64 : 80 }
    }

    // MARK: - 字体大小 (动态)

    enum FontSize {
        /// Toolbar 图标
        static var toolbarIcon: CGFloat { DesignConstants.isCompact ? 16 : 18 }
    }
}
