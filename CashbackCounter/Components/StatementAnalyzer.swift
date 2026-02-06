import UIKit

struct StatementAnalyzer {
    func analyze(image: UIImage) async -> [RecognizedRow] {
        let observations = await OCRService.recognizeObservations(from: image, languages: Self.statementOcrLanguages)
        return OCRService.reconstructRows(from: observations)
    }

    private static let statementOcrLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP"]
}
