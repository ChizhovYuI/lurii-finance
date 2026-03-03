import Foundation

extension String {
    /// Returns the asset name for a source icon, or nil if no icon exists
    func sourceIconName() -> String? {
        switch self.lowercased() {
        case "okx":
            return "okx"
        case "binance":
            return "binance"
        case "binance_th":
            return "binance_th"
        case "bybit":
            return "bybit"
        case "lobstr":
            return "lobstr"
        case "wise":
            return "wise"
        case "kbank":
            return "kbank"
        case "ibkr":
            return "ibkr"
        case "blend":
            return "blend"
        case "revolut":
            return "revolut"
        case "yo":
            return "yo"
        case "rabby":
            return "rabby"
        case "bitget_wallet":
            return "bitget_wallet"
        case "mexc":
            return "mexc"
        default:
            return nil
        }
    }
}
