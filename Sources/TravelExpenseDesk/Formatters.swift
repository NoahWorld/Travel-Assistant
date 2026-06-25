import Foundation

enum AppFormatters {
    static let currency: FloatingPointFormatStyle<Double>.Currency = .currency(code: "CNY")
        .precision(.fractionLength(2))

    static let number: FloatingPointFormatStyle<Double> = .number
        .precision(.fractionLength(0...2))

    static let date: Date.FormatStyle = .dateTime.year().month().day()

    static let shortDateTime: Date.FormatStyle = .dateTime
        .year()
        .month()
        .day()
        .hour()
        .minute()
}
