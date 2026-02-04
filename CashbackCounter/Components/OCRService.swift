//
//  OCRService.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/24/25.
//

import Vision
import UIKit
import FoundationModels // 引入 AI 框架
import ImageIO          // 用于处理图片方向

struct OCRService {
    
    @MainActor static let aiParser = ReceiptParser()
    
    // MARK: - 🚀 总入口：智能双重分析 (节省一次 AI 调用版)
    @MainActor
    static func analyzeImage(_ image: UIImage, region: Region? = nil) async -> ReceiptMetadata? {
        
        // 🟢 情况 A：用户已经在界面上选好了地区 (比如手动选了日本)
        // 直接用该地区的优化语言进行一次精准识别，省流且快。
        if let userRegion = region {
            print("🎯 用户已指定地区: \(userRegion.rawValue)，直接进行精准识别")
            let rawText = await recognizeText(from: image, languages: getLanguages(for: userRegion))
            return try? await aiParser.parse(text: rawText)
        }
        
        // 🟠 情况 B：用户没选地区 (默认模式) -> 启动“本地推断 + 双重扫描”策略
        print("🔍 未指定地区，启动第一轮：通用探索模式...")
        
        // 1. 第一轮 OCR：使用通用语言列表
        let broadLanguages = ["zh-Hans", "en-US", "ja-JP", "zh-Hant"]
        let firstPassText = await recognizeText(from: image, languages: broadLanguages)
        print(firstPassText)
        
        // 2. ⚡️ 本地快速推断 (不调 AI，只查关键词)
        let detectedRegion = simpleInferRegion(from: firstPassText)
        print("⚡️ 本地推断地区: \(detectedRegion?.rawValue ?? "未知")")

        var finalText = firstPassText
        
        // 3. 决策：需要重扫吗？
        if let targetRegion = detectedRegion {
            // 如果推断出了特定地区，为了保证准确率（特别是日语片假名），用专用语言包重扫
            print("🔄 启动第二轮：针对 \(targetRegion.rawValue) 的精准识别...")
            
            let optimizedLanguages = getLanguages(for: targetRegion)
            // 只有当优化后的语言列表跟通用列表不一样时，才值得重扫
            if optimizedLanguages != broadLanguages {
                finalText = await recognizeText(from: image, languages: optimizedLanguages)
            }
        }else{
            
        }
        
        // 4. 最终只调用一次 AI
        print("🤖以此文本请求 AI 分析...")
        return try? await aiParser.parse(text: finalText)
    }
    
    // MARK: - 🕵️‍♂️ 本地侦探：根据文字猜地区
    // 这是一个纯字符串匹配方法，速度极快
    static func simpleInferRegion(from text: String) -> Region? {
        let upperText = text.uppercased()
        
        // 1. 强特征：直接看货币代码 (ISO Code)
        if upperText.contains("JPY") || text.contains("円") { return .jp }
        if upperText.contains("HKD") || text.contains("HK$") { return .hk }
        if upperText.contains("TWD") || upperText.contains("NT$") { return .tw }
        if upperText.contains("NZD") { return .nz }
        if upperText.contains("CNY") || upperText.contains("RMB") || text.contains("人民币"){ return .cn }
        if upperText.contains("USD") { return .us }
        
        // 2. 弱特征：看地名或特殊符号 (如果货币没找到)
        if upperText.contains("合計") || upperText.contains("料金") { return .jp }
        if upperText.contains("HONG KONG") { return .hk }
        if upperText.contains("TAIPEI") || text.contains("台灣") { return .tw }
        if upperText.contains("USA") || upperText.contains("US$") { return .us }
        
        // 3. 符号特征 (¥ 比较难办，中日都用，默认不处理或按概率给一个)
        if text.contains("金额") || text.contains("交易") { return .cn }
        
        return nil
    }
    
    // 获取各地区的最佳语言优先级
    static func getLanguages(for region: Region) -> [String] {
        switch region {
        case .jp:
            // 日本：必须把 ja-JP 放第一
            return ["ja-JP", "en-US", "zh-Hans"]
        case .cn:
            // 简中区
            return ["zh-Hans", "en-US", "ja-JP"]
        case .hk, .tw:
            // 繁中区
            return ["zh-Hant", "en-US", "ja-JP"]
        case .us, .nz, .other:
            // 英语区
            return ["en-US", "zh-Hans", "ja-JP"]
        }
    }
    
    // MARK: - Vision 基础能力 (不变)
    static func recognizeText(from image: UIImage, languages: [String]) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = cgImageOrientation(from: image.imageOrientation)
        
        return await withCheckedContinuation { continuation in
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    continuation.resume(returning: "")
                    return
                }
                let fullText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: fullText)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            try? requestHandler.perform([request])
        }
    }
    
    static func cgImageOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
