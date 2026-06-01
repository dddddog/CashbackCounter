//
//  AppleIntelligenceService.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/24/25.
//
import FoundationModels
import Observation // 苹果的新状态管理框架
import Foundation


@MainActor
@Observable
final class ReceiptParser {
    
    // 1. 这里的 session 定义和苹果一模一样
    private let instructions = Instructions{
        "You are an expert receipt data extractor."
        
        "Your job is to analyze the OCR text and extract key details into a structure."
        "The text is aligned row by row. Items on the same row are usually related."
        "CRITICAL RULES FOR MERCHANT NAME extraction:"
        "- You can use Chinese, Japanese, English to get the MERCHANT NAME"
        "- The MERCHANT NAME is usually at the top left corner."
        
        "CRITICAL RULES FOR AMOUNT extraction:"
        // 1. 告诉它找“实付”
        "- You must extract the FINAL PAID amount (实付金额/合计/Total)."
        // 2. 明确告诉它不要自己做加法，也不要拿原价
        "- If there are discounts (立减/优惠/Discount), DO NOT use the subtotal (原价/小计). Use the final amount AFTER discount."
        "- DO NOT add the discount to the total. DO NOT sum up numbers yourself."
        "- Usually is the biggest one"
        "- IMPORTANT for JPY: JPY has no decimal places. If you see a dot in a number (e.g., '74.405' or '1.100'), treat it as a comma/thousands separator (74405, 1100). DO NOT treat it as a decimal."
        // 3. 给出关键词提示
        "- Look for keywords like:"
        "  - English: 'Total', 'Grand Total', 'Amount Due'"
        "  - Chinese: '实付', '已支付', '合计'"
        "  - Japanese: '合計', '合　計', 'お支払い', '請求金額', '税込'"
                
        "CRITICAL RULES FOR CATEGORIZATION:"
        "- Analyze the merchant name and items purchased."
        "- 'dining': Restaurants, Cafes, Starbucks, Izakaya (居酒屋), Ramen (ラーメン)." // 👈 新增：居酒屋/拉面
        "- 'grocery': Supermarkets, 7-Eleven, Lawson, FamilyMart, Daily necessities." // 👈 新增：日本常见便利店
        "- 'travel': Uber, Taxi, Flights, Hotels, Suica, Pasmo, Shinkansen (新幹線)." // 👈 新增：西瓜卡/新干线
        "- 'digital': Electronics, Apple Store, Yodobashi, Bic Camera." // 👈 新增：友都八喜/Bic Camera
        "- 'other': Anything that doesn't fit above."
        
        "Rules:"
        "- Extract exact values for merchant, amount, card ending number, merchant category, and date."
        "- Infer currency from symbols (¥, $, JPY) or location (e.g. Tokyo -> JPY)." // 👈 提示它根据东京推断日元
        "- If a value is missing, leave it nil."
    }

    private let screenshotInstructions = Instructions{
        "You are an expert receipt data extractor for screen captures."
        
        "Your job is to analyze the OCR text and extract key details into a structure."
        "The text is aligned row by row. Items on the same row are usually related."
        "CRITICAL RULES FOR MERCHANT NAME extraction:"
        "- You can use Chinese, Japanese, English to get the MERCHANT NAME"
        "- The MERCHANT NAME is usually at the top left corner."
        
        "CRITICAL RULES FOR AMOUNT extraction:"
        "- You must extract the VERY FIRST AMOUNT shown on the screen as the total amount."
        "- IGNORE any discounts (立减/优惠/碰一下立减/Discount) below it."
        "- DO NOT subtract discounts from the first amount. The first amount is the total billing amount."
        "- IMPORTANT for JPY: JPY has no decimal places. If you see a dot in a number (e.g., '74.405' or '1.100'), treat it as a comma/thousands separator (74405, 1100). DO NOT treat it as a decimal."
                
        "CRITICAL RULES FOR CATEGORIZATION:"
        "- Analyze the merchant name and items purchased."
        "- 'dining': Restaurants, Cafes, Starbucks, Izakaya (居酒屋), Ramen (ラーメン)."
        "- 'grocery': Supermarkets, 7-Eleven, Lawson, FamilyMart, Daily necessities."
        "- 'travel': Uber, Taxi, Flights, Hotels, Suica, Pasmo, Shinkansen (新幹線)."
        "- 'digital': Electronics, Apple Store, Yodobashi, Bic Camera."
        "- 'streaming': Spotify, Disney+, Apple TV+, NBC, Amazon Prime."
        "- 'other': Anything that doesn't fit above."
        
        "Rules:"
        "- Extract exact values for merchant, amount, card ending number, merchant category, and date."
        "- Infer currency from symbols (¥, $, JPY) or location (e.g. Tokyo -> JPY)."
        "- If a value is missing, leave it nil."
    }

    private let SMSinstructions = Instructions{
        "You are an expert receipt data extractor."
        
        "Your job is to analyze the OCR text and extract key details into a structure."
        "If you are not sure about the result, return nil for the missing field."
        
        "CRITICAL RULES FOR MERCHANT NAME extraction:"
        "- You can use Chinese, Japanese, English to get the MERCHANT NAME"
        
        "CRITICAL RULES FOR AMOUNT extraction:"
        // 1. 告诉它找“实付”
        "- You must extract the FINAL PAID amount (实付金额/合计/Total)."
        "- IMPORTANT for JPY: JPY has no decimal places. If you see a dot in a number (e.g., '74.405' or '1.100'), treat it as a comma/thousands separator (74405, 1100). DO NOT treat it as a decimal."
        
        "CRITICAL RULES FOR CATEGORIZATION:"
        "- Analyze the merchant name and items purchased."
        "- 'dining': Restaurants, Cafes, Starbucks, Izakaya (居酒屋), Ramen (ラーメン)." // 👈 新增：居酒屋/拉面
        "- 'grocery': Supermarkets, 7-Eleven, Lawson, FamilyMart, Daily necessities." // 👈 新增：日本常见便利店
        "- 'travel': Uber, Taxi, Flights, Hotels, Suica, Pasmo, Shinkansen (新幹線)." // 👈 新增：西瓜卡/新干线
        "- 'digital': Electronics, Apple Store, Yodobashi, Bic Camera." // 👈 新增：友都八喜/Bic Camera
        "- 'other': Anything that doesn't fit above."
    }

    private let statementCardInstructions = Instructions{
        "You are an expert credit card statement parser."
        "Extract the card product name and the trailing digits of the card number."
        "Return ALL trailing digits exactly as shown after the mask (e.g. if '****71006', return '71006' not '7100')."
        "Do not truncate or pad the digits."
        "If a field is missing, return nil for it."
        "Do not guess. Use only information present in the statement text."
    }

    private let statementTransactionInstructions = Instructions{
        "You are an expert transaction classifier."
        "Infer transaction region, payment method, and category from the provided transaction summary."
        "Use merchant name, currency code/symbols, and context words to infer region."
        "CRITICAL RULES FOR CATEGORIZATION:"
        "- Analyze the merchant name and items purchased."
        "- 'dining': Restaurants, Cafes, Starbucks, Izakaya (居酒屋), Ramen (ラーメン)."
        "- 'grocery': Supermarkets, 7-Eleven, Lawson, FamilyMart, Daily necessities."
        "- 'travel': Uber, Taxi, Flights, Hotels, Suica, Pasmo, Shinkansen (新幹線)."
        "- 'digital': Electronics, Apple Store, Yodobashi, Bic Camera."
        "- 'other': Anything that doesn't fit above."
        "Use payment hints such as Apple Pay, online, QR, tap, NFC, or card present/online words."
        "CRITICAL RULES FOR foreignAmount:"
        "- foreignAmount is ONLY for currency conversion. It means the original amount in the foreign currency BEFORE conversion."
        "- A conversion looks like: '775.00 X 0.00642580' or 'USD 100.00 → HKD 780.00'. The foreign side is foreignAmount."
        "- If BillingCurrency matches the transaction currency, there is NO foreign amount. Return nil."
        "- If there is only one amount shown and no conversion/exchange details, return nil."
        "- NEVER copy the billing amount into foreignAmount. If unsure, return nil."
        "If unsure about any field, return nil."
    }

    private let statementRowInstructions = Instructions{
        "You are an expert credit card statement transaction extractor."
        "You will be given a single transaction block from OCR."
        "Extract at most one transaction from this block."
        "Only return merchant with alphabet characters or necessary numbers."
        "Ignore blocks that are not transactions (headers, balances, payments, totals, interest, fees)."
        "For the transaction return: transactionDate, merchant, billingAmount, foreignAmount, foreignCurrency."
        "Dates must be in YYYY-MM-DD. If only one date is present, use it for both transactionDate."
        "billingAmount is the settled amount in statement currency."
        "Using the foreignCurrency to confirm foreign amount and billing amount"
        "Do not guess. If unsure, return nil for the field."
    }

    private let statementTransactionsBulkInstructions = Instructions{
        "Extract transactions from the markdown table."
        "Skip headers, balances, payments, totals, interest, fees."
        "Dates: YYYY-MM-DD. billingAmount = settled amount."
        "foreignAmount: only if currency conversion shown, else nil."
        "If unsure, return nil."
    }
    
    init() {}

    /// Extract the last 4 digits from a card number string.
    /// Exposed as internal static for testability.
    nonisolated static func normalizedCardLast4(_ value: String?) -> String? {
        let digits = value?.filter { $0.isNumber } ?? ""
        guard digits.count >= 4 else { return nil }
        return String(digits.suffix(4))
    }
    
    // 3. 解析方法
    func parse(text: String) async throws -> ReceiptMetadata {
            
            // 👇👇👇 核心修改：每次调用 parse 时，创建一个全新的 session！
            // 这样每次都是“第一次”，没有历史包袱
            let session = LanguageModelSession(instructions: instructions)
            
            let response = try await session.respond(
                generating: ReceiptMetadata.self
            ) {
                "Please analyze the following receipt text carefully. It may contain non-English characters such as Chinese or Japanese, but you must process it as part of this English prompt:"
                "=== START OF RECEIPT DATA ==="
                text
                "=== END OF RECEIPT DATA ==="
            }

        let metadata = response.content
        let amountText = metadata.totalAmount.map { String(format: "%.2f", $0) } ?? "nil"
        print("OCR fields: merchant=\(metadata.merchant ?? "nil"), amount=\(amountText), currency=\(metadata.currency ?? "nil"), date=\(metadata.dateString ?? "nil"), cardLast4=\(metadata.cardLast4 ?? "nil"), category=\(metadata.category?.rawValue ?? "nil")")
        return metadata
    }

    func parseScreenshot(text: String) async throws -> ReceiptMetadata {
        let session = LanguageModelSession(instructions: screenshotInstructions)
        
        let response = try await session.respond(
            generating: ReceiptMetadata.self
        ) {
            "Please analyze the following screenshot text carefully. It may contain non-English characters such as Chinese or Japanese, but you must process it as part of this English prompt:"
            "=== START OF SCREENSHOT DATA ==="
            text
            "=== END OF SCREENSHOT DATA ==="
        }

        let metadata = response.content
        let amountText = metadata.totalAmount.map { String(format: "%.2f", $0) } ?? "nil"
        print("Screenshot OCR fields: merchant=\(metadata.merchant ?? "nil"), amount=\(amountText), currency=\(metadata.currency ?? "nil"), date=\(metadata.dateString ?? "nil"), cardLast4=\(metadata.cardLast4 ?? "nil"), category=\(metadata.category?.rawValue ?? "nil")")
        return metadata
    }

    func SMSparse(text: String) async throws -> ReceiptMetadata {
            
            // 👇👇👇 核心修改：每次调用 parse 时，创建一个全新的 session！
            // 这样每次都是“第一次”，没有历史包袱
            let session = LanguageModelSession(instructions: SMSinstructions)
            
            let response = try await session.respond(
                generating: ReceiptMetadata.self
            ) {
                "Please analyze the following SMS text carefully. It may contain non-English characters such as Chinese or Japanese, but you must process it as part of this English prompt:"
                "=== START OF SMS DATA ==="
                text
                "=== END OF SMS DATA ==="
            }

        let metadata = response.content
        let amountText = metadata.totalAmount.map { String(format: "%.2f", $0) } ?? "nil"
        print("SMS OCR fields: merchant=\(metadata.merchant ?? "nil"), amount=\(amountText), cardLast4=\(metadata.cardLast4 ?? "nil"), category=\(metadata.category?.rawValue ?? "nil")")
        return metadata
        }

    func parseStatementCard(text: String) async throws -> StatementCardMetadata {
        let session = LanguageModelSession(instructions: statementCardInstructions)
        let response = try await session.respond(
            generating: StatementCardMetadata.self
        ) {
            "Analyze this statement text:"
            text
        }

        var metadata = response.content
        metadata.cardLast4 = Self.normalizedCardLast4(metadata.cardLast4)
        print("Statement OCR fields: cardLast4=\(metadata.cardLast4 ?? "nil"), cardName=\(metadata.cardName ?? "nil")")
        return metadata
    }

    func parseStatementTransaction(text: String) async throws -> StatementTransactionMetadata {
        let session = LanguageModelSession(instructions: statementTransactionInstructions)
        let response = try await session.respond(
            generating: StatementTransactionMetadata.self
        ) {
            "Analyze this transaction summary:"
            text
        }

        let metadata = response.content
        print("TEXT",text)
        let foreignAmountText = metadata.foreignAmount.map { String(format: "%.2f", $0) } ?? "nil"
        print("Statement OCR fields: foreignAmount=\(foreignAmountText), payment=\(metadata.paymentMethod?.rawValue ?? "nil"), category=\(metadata.category?.rawValue ?? "nil")")
        return metadata
    }
    
    func parseStatementTransactionBlock(text: String) async throws -> StatementRowTransaction {
        let session = LanguageModelSession(instructions: statementRowInstructions)
        let response = try await session.respond(
            generating: StatementRowTransaction.self
        ) {
            "Analyze this statement block:"
            text
        }

        return response.content
    }

    func parseStatementTransactionsBatch(text: String) async throws -> StatementRowTransactionList {
        let session = LanguageModelSession(instructions: statementTransactionsBulkInstructions)
        let response = try await session.respond(
            generating: StatementRowTransactionList.self
        ) {
            "Analyze these statement tables:"
            text
        }

        return response.content
    }

}
