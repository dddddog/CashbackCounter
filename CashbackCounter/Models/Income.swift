import Foundation
import SwiftData

@Model
class Income: Identifiable {
    var amount: Double = 0.0
    var date: Date = Date()
    var location: Region = Region.cn
    var detail : String = ""
    var platform : String = ""
    var isReceived: Bool = false
    
    @Relationship(deleteRule: .nullify)
    var transaction: Transaction?
    
    init(amount: Double, date: Date, location: Region, transaction: Transaction? = nil, detail: String = "",platform : String = "", isReceived: Bool = false) {
        self.amount = amount
        self.date = date
        self.location = location
        self.transaction = transaction
        self.detail = detail
        self.platform = platform
        self.isReceived = isReceived
    }
    private static let _dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var dateString: String {
        Self._dateFormatter.string(from: date)
    }
}
