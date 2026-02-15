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
    private let SMSinstructions = Instructions{
        "You are an expert receipt data extractor."
        
        "Your job is to analyze the OCR text and extract key details into a structure."
        "If you are not sure about the result, return nil for the missing field."
        
        "CRITICAL RULES FOR MERCHANT NAME extraction:"
        "- You can use Chinese, Japanese, English to get the MERCHANT NAME"
        
        "CRITICAL RULES FOR AMOUNT extraction:"
        // 1. 告诉它找“实付”
        "- You must extract the FINAL PAID amount (实付金额/合计/Total)."
        
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
        "Extract the card product name and the last 4 digits of the card."
        "If a field is missing, return nil for it."
        "Do not guess. Use only information present in the statement text."
        "Extract the card product name and the last 4 digits of the card."
        "If a field is missing, return nil for it."
        "Do not guess. Use only information present in the statement text."
    }

    private let statementTransactionInstructions = Instructions{
        "You are an expert transaction classifier."
        "Infer transaction region, payment method, and category from the provided transaction summary."
        "Use merchant name, currency code/symbols, and context words to infer region."
        "CRITICAL RULES FOR CATEGORIZATION:"
        "- Analyze the merchant name and items purchased."
        "- 'dining': Restaurants, Cafes, Starbucks, Izakaya (居酒屋), Ramen (ラーメン)." // 👈 新增：居酒屋/拉面
        "- 'grocery': Supermarkets, 7-Eleven, Lawson, FamilyMart, Daily necessities." // 👈 新增：日本常见便利店
        "- 'travel': Uber, Taxi, Flights, Hotels, Suica, Pasmo, Shinkansen (新幹線)." // 👈 新增：西瓜卡/新干线
        "- 'digital': Electronics, Apple Store, Yodobashi, Bic Camera." // 👈 新增：友都八喜/Bic Camera
        "- 'other': Anything that doesn't fit above."
        "Use payment hints such as Apple Pay, online, QR, tap, NFC, or card present/online words."
        "Extract the original transaction amount in foreign currency if the statement shows exchange details."
        "Original transaction amount in foreign currency. If there's a X between 2 numbers(like 775.00 X 0.00642580), the first number(775) is the foreignAmount. NOT SAME AS BILLING AMOUNT, Return nil if not present."
        "Do not return the billing/settlement amount as foreignAmount."
        "Extract the original transaction amount in foreign currency if the statement shows exchange details."
        "Original transaction amount in foreign currency. If there's a X between 2 numbers(like 775.00 X 0.00642580), the first number(775) is the foreignAmount. NOT SAME AS BILLING AMOUNT, Return nil if not present."
        "Do not return the billing/settlement amount as foreignAmount."
        "If unsure, return nil for the field."
    }

    private let statementRowInstructions = Instructions{
        "You are an expert credit card statement transaction extractor."
        "You will be given a single transaction block from OCR."
        "Extract at most one transaction from this block."
        "Only return merchant with alphabet characters or necessary numbers."
        "Only return merchant with alphabet characters or necessary numbers."
        "Ignore blocks that are not transactions (headers, balances, payments, totals, interest, fees)."
        "Ignore blocks that are not transactions (headers, balances, payments, totals, interest, fees)."
        "For the transaction return: transactionDate, merchant, billingAmount, foreignAmount, foreignCurrency."
        "For the transaction return: transactionDate, merchant, billingAmount, foreignAmount, foreignCurrency."
        "Dates must be in YYYY-MM-DD. If only one date is present, use it for both transactionDate."
        "billingAmount is the settled amount in statement currency."
        "Using the foreignCurrency to confirm foreign amount and billing amount"
        "Using the foreignCurrency to confirm foreign amount and billing amount"
        "Do not guess. If unsure, return nil for the field."
        "Do not guess. If unsure, return nil for the field."
    }
    
    init() {}

    private func normalizedCardLast4(_ value: String?) -> String? {
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
                "Analyze this receipt text:"
                text
            }

        let metadata = response.content
        let amountText = metadata.totalAmount.map { String(format: "%.2f", $0) } ?? "nil"
        print("OCR fields: merchant=\(metadata.merchant ?? "nil"), amount=\(amountText), currency=\(metadata.currency ?? "nil"), date=\(metadata.dateString ?? "nil"), cardLast4=\(metadata.cardLast4 ?? "nil"), category=\(metadata.category?.rawValue ?? "nil")")
        return metadata
        }
    func SMSparse(text: String) async throws -> ReceiptMetadata {
            
            // 👇👇👇 核心修改：每次调用 parse 时，创建一个全新的 session！
            // 这样每次都是“第一次”，没有历史包袱
            let session = LanguageModelSession(instructions: SMSinstructions)
            
            let response = try await session.respond(
                generating: ReceiptMetadata.self
            ) {
                "Analyze this receipt text:"
                text
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
        metadata.cardLast4 = normalizedCardLast4(metadata.cardLast4)
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

}
