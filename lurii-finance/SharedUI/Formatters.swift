import Foundation

enum ValueFormatters {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    static func currency(from value: String?, code: String?) -> String? {
        guard let value, let code, let decimal = Decimal(string: value) else {
            return nil
        }

        let formatter = currencyFormatter
        let uppercased = code.uppercased()
        formatter.currencyCode = uppercased
        if uppercased == "USD" {
            formatter.currencySymbol = "$"
        }

        return formattedWithBounds(decimal: decimal, formatter: formatter, scale: 2)
    }

    static func percent(from value: String?) -> String? {
        guard let value, let decimal = Decimal(string: value) else {
            return nil
        }

        let normalized = decimal > 1 ? decimal / 100 : decimal
        return formattedWithBounds(decimal: normalized, formatter: percentFormatter, scale: 4)
    }

    static func percentFromPercentValue(_ value: String?) -> String? {
        guard let value, let decimal = Decimal(string: value) else {
            return nil
        }

        let normalized = decimal / 100
        return formattedWithBounds(decimal: normalized, formatter: percentFormatter, scale: 4)
    }

    static func number(from value: String?) -> String? {
        guard let value, let decimal = Decimal(string: value) else {
            return nil
        }

        return formattedWithBounds(decimal: decimal, formatter: numberFormatter, scale: 2)
    }

    private static func formattedWithBounds(decimal: Decimal, formatter: NumberFormatter, scale: Int) -> String? {
        let rounded = decimalRounded(decimal, scale: scale, mode: .plain)
        return formatter.string(from: rounded as NSDecimalNumber)
    }

    private static func decimalRounded(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }
}
