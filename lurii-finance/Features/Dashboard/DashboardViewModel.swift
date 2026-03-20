import Combine
import SwiftUI

enum DashboardDateRange: String, CaseIterable, Identifiable {
    case oneWeek = "1W"
    case monthToDate = "MTD"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case yearToDate = "YTD"
    case oneYear = "1Y"
    case all = "All"

    var id: String { rawValue }

    var pnlPeriod: String {
        switch self {
        case .oneWeek:
            return "1w"
        case .monthToDate:
            return "mtd"
        case .oneMonth:
            return "1m"
        case .threeMonths:
            return "3m"
        case .yearToDate:
            return "ytd"
        case .oneYear:
            return "1y"
        case .all:
            return "all"
        }
    }

    var pnlTitle: String {
        "\(rawValue) PnL"
    }

    var pnlSubtitle: String {
        switch self {
        case .all:
            return "Change over available history"
        default:
            return "Change over the selected range"
        }
    }

    func historyDays(endingOn isoDate: String?) -> Int {
        guard let isoDate, let endDate = Self.dateFormatter.date(from: isoDate) else {
            return fallbackHistoryDays
        }

        let calendar = Calendar(identifier: .gregorian)

        switch self {
        case .oneWeek:
            return 7
        case .monthToDate:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate)) ?? endDate
            return Self.dayCount(from: start, to: endDate, calendar: calendar)
        case .oneMonth:
            return 30
        case .threeMonths:
            return 90
        case .yearToDate:
            let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: endDate), month: 1, day: 1)) ?? endDate
            return Self.dayCount(from: start, to: endDate, calendar: calendar)
        case .oneYear:
            return 365
        case .all:
            return 365_000
        }
    }

    private var fallbackHistoryDays: Int {
        switch self {
        case .oneWeek:
            return 7
        case .monthToDate:
            return 31
        case .oneMonth:
            return 30
        case .threeMonths:
            return 90
        case .yearToDate:
            return 366
        case .oneYear:
            return 365
        case .all:
            return 365_000
        }
    }

    /// Returns an ISO date string for the start of this range, given an end date.
    func startDate(endingOn isoDate: String?) -> String? {
        guard let isoDate, let endDate = Self.dateFormatter.date(from: isoDate) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let start: Date?
        switch self {
        case .oneWeek:
            start = calendar.date(byAdding: .day, value: -6, to: endDate)
        case .monthToDate:
            start = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate))
        case .oneMonth:
            start = calendar.date(byAdding: .day, value: -29, to: endDate)
        case .threeMonths:
            start = calendar.date(byAdding: .day, value: -89, to: endDate)
        case .yearToDate:
            start = calendar.date(from: DateComponents(year: calendar.component(.year, from: endDate), month: 1, day: 1))
        case .oneYear:
            start = calendar.date(byAdding: .day, value: -364, to: endDate)
        case .all:
            return nil
        }
        guard let start else { return nil }
        return Self.dateFormatter.string(from: start)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dayCount(from startDate: Date, to endDate: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return max(days + 1, 1)
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var summary: PortfolioSummary?
    @Published var netWorthHistory: [NetWorthHistoryPoint] = []
    @Published var pnl: PnlResponse?
    @Published var allocation: AllocationResponse?
    @Published var sourceMovers: SourceMoversResponse?
    @Published var earnSummary: EarnSummaryResponse?
    @Published var txAnalytics: TransactionAnalyticsSummary?
    @Published var monthlyTrends: [MonthlyTrendPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var loadTask: Task<Void, Never>?
    private var loadSequence = 0

    nonisolated init() {}

    func load(range: DashboardDateRange = .oneMonth) {
        loadTask?.cancel()
        loadSequence += 1
        let sequence = loadSequence

        isLoading = true
        errorMessage = nil

        loadTask = Task {
            defer {
                if sequence == self.loadSequence {
                    self.isLoading = false
                }
            }

            do {
                async let summaryTask = APIClient.shared.getPortfolioSummary()
                async let pnlTask = APIClient.shared.getPnl(period: range.pnlPeriod)
                async let allocationTask = APIClient.shared.getAllocation()
                async let sourceMoversTask = APIClient.shared.getSourceMovers()
                async let earnSummaryTask = APIClient.shared.getEarnSummary()
                async let trendsTask = APIClient.shared.getMonthlyTrends(months: 6)

                let summary = try await summaryTask
                async let historyTask = APIClient.shared.getPortfolioNetWorthHistory(days: range.historyDays(endingOn: summary.date))
                async let txAnalyticsTask = APIClient.shared.getTransactionAnalyticsSummary(start: range.startDate(endingOn: summary.date), end: summary.date)
                let history = try? await historyTask
                let pnl = try? await pnlTask
                let allocation = try? await allocationTask
                let sourceMovers = try? await sourceMoversTask
                let earnSummary = try? await earnSummaryTask
                let txAnalytics = try? await txAnalyticsTask
                let trends = try? await trendsTask

                guard !Task.isCancelled, sequence == self.loadSequence else { return }

                self.summary = summary
                self.netWorthHistory = history?.points ?? []
                self.pnl = pnl
                self.allocation = allocation
                self.sourceMovers = sourceMovers
                self.earnSummary = earnSummary
                self.txAnalytics = txAnalytics
                self.monthlyTrends = trends?.months ?? []
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, sequence == self.loadSequence else { return }
                self.summary = nil
                self.netWorthHistory = []
                self.pnl = nil
                self.allocation = nil
                self.sourceMovers = nil
                self.earnSummary = nil
                self.txAnalytics = nil
                self.monthlyTrends = []
                self.errorMessage = "Unable to load dashboard data: \(error.localizedDescription)"
            }
        }
    }
}
