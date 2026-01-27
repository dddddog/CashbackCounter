//
//  PaymentMethod.swift
//  CashbackCounter
//
//  Created by CashbackCounter Assistant.
//

import FoundationModels
import Foundation
import SwiftUI

@Generable
enum PaymentMethod: String, CaseIterable, Codable {
    // 定义所有的消费方式 (Key)
    case applePay       // Apple Pay
    case webShopping    // 网购
    case qrCode         // QR Code
    case offline        // 线下消费
    case online         // 线上消费
    
    // 计算属性：专门负责返回对应的图标 (使用 SF Symbols)
    var iconName: String {
        switch self {
        case .applePay: return "apple.logo"           // Apple Logo
        case .webShopping: return "cart.fill"         // 购物车，代表网购
        case .qrCode: return "qrcode.viewfinder"      // 二维码扫描框
        case .offline: return "storefront.fill"       // 店铺，代表线下
        case .online: return "globe"                  // 地球，代表线上/网络
        }
    }
    
    // 计算属性：返回给人看的名称
    var displayName: String {
        switch self {
        case .applePay: return "Apple Pay"
        case .webShopping: return "网购"
        case .qrCode: return "QR Code"
        case .offline: return "线下消费"
        case .online: return "线上消费"
        }
    }
    
    // 计算属性：对应的颜色 (用于图表或标签背景)
    var color: Color {
        switch self {
        case .applePay: return .primary    // 黑色 (深色模式下为白)，符合 Apple 风格
        case .webShopping: return .orange  // 橙色，常见于电商 App
        case .qrCode: return .blue         // 蓝色，常见于支付软件
        case .offline: return .green       // 绿色，代表实体/现金流
        case .online: return .purple       // 紫色，代表互联网服务
        }
    }
}
