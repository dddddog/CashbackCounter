//
//  ReceiptModels.swift
//  CashbackCounter
//
//  Created by Junhao Huang on 11/24/25.
//

import Foundation
import FoundationModels

// 1. 定义收据结构 (对应 Apple 的 Itinerary)
@Generable
struct ReceiptMetadata {
    @Guide(description: "The name of the store or merchant.")
    var merchant: String?  // ✅ 加上问号
    
    @Guide(description: "The total amount paid (not contain deduction).")
    var totalAmount: Double? // ✅ 加上问号
    
    @Guide(description: "The currency code (choice from those, CNY, USD, HKD, JPY, NZD, TWD, GBP, MOP, EUR).")
    var currency: String?    // ✅ 加上问号
    
    @Guide(description: "The date of transaction in YYYY-MM-DD format.")
    var dateString: String?  // ✅ 加上问号
    
    @Guide(description: "The last 4 digits of the credit card used.")
    var cardLast4: String?   // ✅ 加上问号
    
    @Guide(description: "Classify the receipt into one of the categories based on the merchant and items")
    var category: Category?
}

@Generable
struct SMSMetadata {
    @Guide(description: "The name of the store or merchant.")
    var merchant: String?  // ✅ 加上问号
    
    @Guide(description: "The total amount paid (not contain deduction).")
    var totalAmount: Double? // ✅ 加上问号
    
    @Guide(description: "The last 4 digits of the credit card used.")
    var cardLast4: String?   // ✅ 加上问号
    
    @Guide(description: "Classify the receipt into one of the categories based on the merchant and items")
    var category: Category?
}

@Generable
struct StatementCardMetadata {
    @Guide(description: "The last 4 digits of the statement card. Return only digits if available.")
    var cardLast4: String?

    @Guide(description: "The card product name or bank name if available.")
    var cardName: String?
}

@Generable
struct StatementTransactionMetadata {
    @Guide(description: "Transaction region. Choose from: cn, hk, us, jp, nz, tw, eu, mo, uk.")
    var region: Region?

    @Guide(description: "Payment method. Choose from: applePay, qrCode, offline, online, pulse, gba.")
    var paymentMethod: PaymentMethod?

    @Guide(description: "Category based on merchant and context.")
    var category: Category?

    @Guide(description: "Original transaction amount in foreign currency. If there's a X between 2 numbers(like 775.00 X 0.00642580), the first number(775) is the foreignAmount. NOT SAME AS BILLING AMOUNT, Return nil if not present.")
    var foreignAmount: Double?

}

@Generable
struct StatementRowTransaction {
    @Guide(description: "Transaction date in YYYY-MM-DD format. Return nil if not present.")
    var transactionDate: String?

    var postDate: String?

    @Guide(description: "Merchant name or description.")
    var merchant: String?

    @Guide(description: "Billing amount in statement currency.")
    var billingAmount: Double?

    @Guide(description: "Original amount in foreign currency if available.")
    var foreignAmount: Double?

    @Guide(description: "Foreign currency code if available (e.g. USD, JPY).")
    var foreignCurrency: String?
    
    var rawText: String?
}

@Generable
struct StatementRowTransactionList {
    @Guide(description: "List of transactions extracted from OCR rows.")
    var transactions: [StatementRowTransaction]
}
