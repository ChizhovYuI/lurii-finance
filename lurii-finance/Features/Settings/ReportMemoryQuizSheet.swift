import SwiftUI

struct ReportMemoryQuizSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var stepIndex = 0
    @State private var answers = ReportMemoryQuizAnswers()
    @State private var generatedMemory = ""
    @State private var isEditingGeneratedMemory = false

    let onUse: (String) -> Void

    private static let maxMemoryLength = 1200
    private let steps = ReportMemoryQuizStep.allSteps

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if isReviewStep {
                reviewView
            } else {
                questionStepView
            }

            footer
        }
        .padding(24)
        .frame(width: 620, height: 760)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Weekly Report Context")
                .font(.title2)

            Text(isReviewStep ? "Review the generated profile before using it." : currentStep.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(isReviewStep ? steps.count : stepIndex), total: Double(steps.count))
                .tint(.secondary)

            if !isReviewStep {
                Text("Step \(stepIndex + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var questionStepView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(currentStep.title)
                    .font(.headline)

                ForEach(currentStep.questions) { question in
                    questionView(question)
                }
            }
        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Generated Markdown")
                    .font(.headline)
                Spacer()
                Text("\(generatedMemory.count)/\(Self.maxMemoryLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isEditingGeneratedMemory {
                ZStack(alignment: .topLeading) {
                    if generatedMemory.isEmpty {
                        Text("Generated profile will appear here.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .padding(.leading, 6)
                    }

                    TextEditor(text: $generatedMemory)
                        .font(DesignTokens.bodyFont)
                        .padding(4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )
            } else {
                ScrollView {
                    Text(generatedMemory)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(DesignTokens.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if isReviewStep {
                Button("Start Over") {
                    answers = ReportMemoryQuizAnswers()
                    generatedMemory = ""
                    isEditingGeneratedMemory = false
                    stepIndex = 0
                }
                .buttonStyle(.bordered)

                Button(isEditingGeneratedMemory ? "Done Editing" : "Edit First") {
                    isEditingGeneratedMemory.toggle()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)

            Button("Back") {
                if isReviewStep {
                    isEditingGeneratedMemory = false
                    stepIndex = max(steps.count - 1, 0)
                } else if stepIndex > 0 {
                    stepIndex -= 1
                }
            }
            .buttonStyle(.bordered)
            .disabled(stepIndex == 0 && !isReviewStep)

            Button(isReviewStep ? "Use This Memory" : (stepIndex == steps.count - 1 ? "Generate Profile" : "Continue")) {
                if isReviewStep {
                    onUse(generatedMemory)
                    dismiss()
                } else if stepIndex == steps.count - 1 {
                    generatedMemory = ReportMemoryGenerator.generate(from: answers, maxLength: Self.maxMemoryLength)
                    isEditingGeneratedMemory = false
                    stepIndex = steps.count
                } else {
                    stepIndex += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)
        }
    }

    @ViewBuilder
    private func questionView(_ question: ReportMemoryQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.label)
                .font(.headline)

            switch question.kind {
            case .select(let options):
                Picker(question.label, selection: singleBinding(question.id)) {
                    Text("Select…").tag("")
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)

            case .multi(let options):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Toggle(option, isOn: multiBinding(question.id, option: option))
                            .toggleStyle(.checkbox)
                    }
                }

            case .shortTextOptional(let placeholder):
                TextField(question.label, text: textBinding(question.id), prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)

            case .longTextOptional(let placeholder):
                ZStack(alignment: .topLeading) {
                    if answers.textValue(for: question.id).isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .padding(.leading, 6)
                    }
                    TextEditor(text: textBinding(question.id))
                        .font(DesignTokens.bodyFont)
                        .frame(minHeight: 120)
                }
                .padding(4)
                .background(DesignTokens.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var isReviewStep: Bool {
        stepIndex >= steps.count
    }

    private var currentStep: ReportMemoryQuizStep {
        steps[min(stepIndex, steps.count - 1)]
    }

    private var canContinue: Bool {
        guard !isReviewStep else {
            return !generatedMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return currentStep.questions.allSatisfy { question in
            switch question.kind {
            case .select:
                return !answers.singleValue(for: question.id).isEmpty
            case .multi:
                return !answers.multiValues(for: question.id).isEmpty
            case .shortTextOptional, .longTextOptional:
                return true
            }
        }
    }

    private func singleBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { answers.singleValue(for: id) },
            set: { answers.setSingle($0, for: id) }
        )
    }

    private func multiBinding(_ id: String, option: String) -> Binding<Bool> {
        Binding(
            get: { answers.multiValues(for: id).contains(option) },
            set: { answers.setMulti(option, enabled: $0, for: id) }
        )
    }

    private func textBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { answers.textValue(for: id) },
            set: { answers.setText($0, for: id) }
        )
    }
}

private struct ReportMemoryQuizStep: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let questions: [ReportMemoryQuizQuestion]

    static let allSteps: [ReportMemoryQuizStep] = [
        ReportMemoryQuizStep(
            id: "location",
            title: "Location & Tax Context",
            subtitle: "This affects taxes, currency risk, and practical portfolio advice.",
            questions: [
                .select(
                    id: "country_of_residence",
                    label: "Country of residence",
                    options: ["Thailand", "UK", "EEA", "UAE", "USA", "Germany", "Russia", "Other"]
                ),
                .select(
                    id: "residency_status",
                    label: "Tax residency status",
                    options: [
                        "Tax resident of current country",
                        "Non-resident / digital nomad",
                        "Split residency / complicated",
                        "Not sure",
                    ]
                ),
                .multi(
                    id: "primary_expense_currency",
                    label: "Primary expense currencies",
                    options: ["THB", "GBP", "USD", "EUR", "AED", "Other"]
                ),
                .multi(
                    id: "housing_obligations",
                    label: "Housing and fixed obligations",
                    options: [
                        "Rent in current country",
                        "Mortgage",
                        "Family support",
                        "No major fixed obligations",
                        "Other",
                    ]
                ),
            ]
        ),
        ReportMemoryQuizStep(
            id: "income",
            title: "Income & Cash Flow",
            subtitle: "This gives the AI context on how the portfolio is funded.",
            questions: [
                .multi(
                    id: "income_sources",
                    label: "Income sources",
                    options: [
                        "Salary",
                        "Freelance / consulting",
                        "Business income",
                        "Rental income",
                        "Dividends / interest",
                        "Crypto income",
                        "Other",
                    ]
                ),
                .multi(
                    id: "income_currency",
                    label: "Income currencies",
                    options: ["GBP", "USD", "EUR", "THB", "USDT / USDC", "Other"]
                ),
                .select(
                    id: "monthly_income_band",
                    label: "Approximate monthly income",
                    options: [
                        "Under $2k",
                        "$2k–5k",
                        "$5k–10k",
                        "$10k–20k",
                        "Over $20k",
                        "Irregular",
                    ]
                ),
                .select(
                    id: "monthly_investing_band",
                    label: "Approximate monthly investing",
                    options: [
                        "Under $500",
                        "$500–1.5k",
                        "$1.5k–3k",
                        "$3k–7k",
                        "Over $7k",
                        "Irregular lump sums",
                    ]
                ),
            ]
        ),
        ReportMemoryQuizStep(
            id: "expenses",
            title: "Expenses & Safety Buffer",
            subtitle: "Liquidity needs and emergency runway matter for advice quality.",
            questions: [
                .select(
                    id: "monthly_expenses_band",
                    label: "Approximate monthly living expenses",
                    options: [
                        "Under $1k",
                        "$1k–2.5k",
                        "$2.5k–5k",
                        "$5k–10k",
                        "Over $10k",
                    ]
                ),
                .select(
                    id: "emergency_fund_status",
                    label: "Emergency fund status",
                    options: [
                        "6+ months of expenses",
                        "3–6 months",
                        "1–3 months",
                        "Less than 1 month",
                        "No real emergency fund",
                    ]
                ),
                .multi(
                    id: "emergency_fund_location",
                    label: "Where is the emergency fund held?",
                    options: [
                        "Bank account",
                        "Wise / multi-currency account",
                        "Local bank",
                        "Stablecoins",
                        "Brokerage money market / cash",
                        "Other",
                    ]
                ),
                .shortTextOptional(
                    id: "emergency_fund_amount",
                    label: "Emergency fund amount",
                    placeholder: "e.g. ~$14,000 in Wise + KBank"
                ),
            ]
        ),
        ReportMemoryQuizStep(
            id: "goals",
            title: "Goals & Horizon",
            subtitle: "This is the main framing context for recommendations.",
            questions: [
                .select(
                    id: "primary_goal",
                    label: "Primary investment goal",
                    options: [
                        "Long-term capital growth",
                        "FIRE / early retirement",
                        "Passive income",
                        "Capital preservation",
                        "Saving for property",
                        "Financial independence without fixed date",
                    ]
                ),
                .select(
                    id: "time_horizon",
                    label: "Time horizon",
                    options: [
                        "Under 1 year",
                        "1–3 years",
                        "3–7 years",
                        "7–15 years",
                        "15+ years",
                    ]
                ),
                .multi(
                    id: "secondary_goal",
                    label: "Secondary goals",
                    options: [
                        "Reduce concentration risk",
                        "Increase passive income",
                        "Build emergency buffer",
                        "Improve tax efficiency",
                        "Simplify portfolio",
                        "Increase upside / growth",
                        "Preserve flexibility for relocation",
                    ]
                ),
            ]
        ),
        ReportMemoryQuizStep(
            id: "risk",
            title: "Risk Profile",
            subtitle: "This gives the model a stable behavioral anchor.",
            questions: [
                .select(
                    id: "drawdown_reaction",
                    label: "How do you react to a 25% drawdown?",
                    options: [
                        "I buy more aggressively",
                        "I mostly hold",
                        "I rebalance defensively",
                        "I reduce risk significantly",
                        "I panic but try not to act",
                    ]
                ),
                .select(
                    id: "max_acceptable_drawdown",
                    label: "Maximum acceptable drawdown",
                    options: [
                        "0–5%",
                        "5–15%",
                        "15–30%",
                        "30–50%",
                        "Any drawdown if thesis is intact and horizon is 10+ years",
                    ]
                ),
                .select(
                    id: "risk_self_assessment",
                    label: "Self-assessed risk profile",
                    options: ["Conservative", "Moderate", "Aggressive", "Very aggressive"]
                ),
            ]
        ),
        ReportMemoryQuizStep(
            id: "experience",
            title: "Experience & Instruments",
            subtitle: "Avoid advice that mismatches your real comfort level.",
            questions: [
                .select(
                    id: "experience_level",
                    label: "Investment experience",
                    options: ["Under 2 years", "2–5 years", "5–10 years", "10+ years"]
                ),
                .multi(
                    id: "comfortable_instruments",
                    label: "Comfortable instruments",
                    options: [
                        "ETFs / index funds",
                        "Individual stocks",
                        "Bonds",
                        "BTC / ETH",
                        "Broader crypto",
                        "DeFi / yield",
                        "REITs / property exposure",
                        "Gold / commodities",
                        "Options / derivatives",
                    ]
                ),
                .select(
                    id: "portfolio_style",
                    label: "Portfolio style",
                    options: [
                        "Mostly passive",
                        "Core passive + some active bets",
                        "Active allocation",
                        "Opportunistic / tactical",
                    ]
                ),
                .select(
                    id: "rebalance_frequency",
                    label: "Rebalancing frequency",
                    options: [
                        "Rarely / almost never",
                        "Quarterly",
                        "Monthly",
                        "Weekly / very active",
                    ]
                ),
            ]
        ),
        ReportMemoryQuizStep(
            id: "constraints",
            title: "Constraints & Preferences",
            subtitle: "Capture things the portfolio data itself will never show.",
            questions: [
                .multi(
                    id: "must_avoid",
                    label: "What should the AI avoid recommending?",
                    options: [
                        "Leverage",
                        "Illiquid assets",
                        "Small caps / speculative names",
                        "DeFi smart-contract risk",
                        "Single-stock concentration",
                        "High tax complexity",
                        "No strong exclusions",
                    ]
                ),
                .multi(
                    id: "preferred_style",
                    label: "Preferred investing style",
                    options: [
                        "Buy the dip",
                        "Long-term compounding",
                        "Income-oriented",
                        "Tax-efficient structure",
                        "Simplicity over optimization",
                        "High conviction concentration",
                    ]
                ),
                .longTextOptional(
                    id: "manual_note",
                    label: "Anything else the AI should keep in mind?",
                    placeholder: "Optional. Add anything stable and relevant that is not captured above."
                ),
            ]
        ),
    ]
}

private struct ReportMemoryQuizQuestion: Identifiable {
    let id: String
    let label: String
    let kind: Kind

    enum Kind {
        case select([String])
        case multi([String])
        case shortTextOptional(String)
        case longTextOptional(String)
    }

    static func select(id: String, label: String, options: [String]) -> ReportMemoryQuizQuestion {
        ReportMemoryQuizQuestion(id: id, label: label, kind: .select(options))
    }

    static func multi(id: String, label: String, options: [String]) -> ReportMemoryQuizQuestion {
        ReportMemoryQuizQuestion(id: id, label: label, kind: .multi(options))
    }

    static func shortTextOptional(id: String, label: String, placeholder: String) -> ReportMemoryQuizQuestion {
        ReportMemoryQuizQuestion(id: id, label: label, kind: .shortTextOptional(placeholder))
    }

    static func longTextOptional(id: String, label: String, placeholder: String) -> ReportMemoryQuizQuestion {
        ReportMemoryQuizQuestion(id: id, label: label, kind: .longTextOptional(placeholder))
    }
}

private struct ReportMemoryQuizAnswers {
    private(set) var single: [String: String] = [:]
    private(set) var multi: [String: [String]] = [:]
    private(set) var text: [String: String] = [:]

    mutating func setSingle(_ value: String, for id: String) {
        single[id] = value
    }

    mutating func setMulti(_ option: String, enabled: Bool, for id: String) {
        var values = multi[id, default: []]
        if enabled {
            if !values.contains(option) {
                values.append(option)
            }
        } else {
            values.removeAll { $0 == option }
        }
        multi[id] = values
    }

    mutating func setText(_ value: String, for id: String) {
        text[id] = value
    }

    func singleValue(for id: String) -> String {
        single[id, default: ""]
    }

    func multiValues(for id: String) -> [String] {
        multi[id, default: []]
    }

    func textValue(for id: String) -> String {
        text[id, default: ""]
    }
}

private enum ReportMemoryGenerator {
    static func generate(from answers: ReportMemoryQuizAnswers, maxLength: Int) -> String {
        var sections: [String] = []

        let locationLines = buildLocationSection(answers)
        if !locationLines.isEmpty {
            sections.append(makeSection(title: "Location & Expenses", lines: locationLines))
        }

        let incomeLines = buildIncomeSection(answers)
        if !incomeLines.isEmpty {
            sections.append(makeSection(title: "Income & Finances", lines: incomeLines))
        }

        let profileLines = buildProfileSection(answers)
        if !profileLines.isEmpty {
            sections.append(makeSection(title: "Investment Profile", lines: profileLines))
        }

        let note = clipSentence(answers.textValue(for: "manual_note"), maxLength: 220)
        if !note.isEmpty {
            sections.append(makeSection(title: "Additional Preferences", lines: [note]))
        }

        let memory = sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard memory.count > maxLength else {
            return memory
        }
        return String(memory.prefix(maxLength - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func buildLocationSection(_ answers: ReportMemoryQuizAnswers) -> [String] {
        var lines: [String] = []

        let country = answers.singleValue(for: "country_of_residence")
        if !country.isEmpty {
            lines.append("Living in \(country).")
        }

        switch answers.singleValue(for: "residency_status") {
        case "Tax resident of current country":
            lines.append("Tax resident of the current country.")
        case "Non-resident / digital nomad":
            lines.append("Non-resident / digital nomad.")
        case "Split residency / complicated":
            lines.append("Tax situation is split or complicated.")
        case "Not sure":
            lines.append("Tax residency is not fully clear.")
        default:
            break
        }

        let expenseCurrencies = answers.multiValues(for: "primary_expense_currency")
        if !expenseCurrencies.isEmpty {
            lines.append("Main expenses in \(humanList(expenseCurrencies, maxItems: 3)).")
        }

        let obligations = answers.multiValues(for: "housing_obligations").filter { $0 != "No major fixed obligations" }
        if answers.multiValues(for: "housing_obligations").contains("No major fixed obligations") && obligations.isEmpty {
            lines.append("No major fixed obligations.")
        } else {
            for obligation in obligations.prefix(3) {
                switch obligation {
                case "Rent in current country":
                    lines.append("Rent in the current country.")
                case "Mortgage":
                    lines.append("Mortgage obligations.")
                case "Family support":
                    lines.append("Regular family support obligations.")
                case "Other":
                    lines.append("Additional fixed obligations.")
                default:
                    break
                }
            }
        }

        return lines
    }

    private static func buildIncomeSection(_ answers: ReportMemoryQuizAnswers) -> [String] {
        var lines: [String] = []

        let incomeSources = answers.multiValues(for: "income_sources")
        if !incomeSources.isEmpty {
            lines.append("Income sources: \(humanList(incomeSources, maxItems: 4)).")
        }

        let incomeCurrencies = answers.multiValues(for: "income_currency")
        if !incomeCurrencies.isEmpty {
            lines.append("Income mostly in \(humanList(incomeCurrencies, maxItems: 3)).")
        }

        let incomeBand = answers.singleValue(for: "monthly_income_band")
        if !incomeBand.isEmpty {
            lines.append("Monthly income: \(incomeBand.lowercased()) equivalent.")
        }

        switch answers.singleValue(for: "monthly_investing_band") {
        case "Irregular lump sums":
            lines.append("Investing is irregular and done in larger contributions.")
        case let value where !value.isEmpty:
            lines.append("Monthly investing: \(value.lowercased()).")
        default:
            break
        }

        let expenseBand = answers.singleValue(for: "monthly_expenses_band")
        if !expenseBand.isEmpty {
            lines.append("Living expenses: \(expenseBand.lowercased()) per month.")
        }

        let emergencyAmount = clipSentence(answers.textValue(for: "emergency_fund_amount"), maxLength: 80)
        let emergencyLocations = answers.multiValues(for: "emergency_fund_location")
        let emergencyStatus = answers.singleValue(for: "emergency_fund_status")

        if !emergencyAmount.isEmpty && !emergencyLocations.isEmpty {
            lines.append("Emergency fund: \(emergencyAmount), held in \(humanList(emergencyLocations, maxItems: 3)).")
        } else if !emergencyAmount.isEmpty {
            lines.append("Emergency fund: \(emergencyAmount).")
        } else if !emergencyStatus.isEmpty {
            lines.append("Emergency fund status: \(emergencyStatus.lowercased()).")
        }

        return lines
    }

    private static func buildProfileSection(_ answers: ReportMemoryQuizAnswers) -> [String] {
        var lines: [String] = []

        let goal = answers.singleValue(for: "primary_goal")
        if !goal.isEmpty {
            lines.append("Primary goal: \(goal).")
        }

        let horizon = answers.singleValue(for: "time_horizon")
        if !horizon.isEmpty {
            lines.append("Horizon: \(horizon).")
        }

        let secondary = answers.multiValues(for: "secondary_goal")
        if !secondary.isEmpty {
            lines.append("Secondary priorities: \(humanList(secondary, maxItems: 4)).")
        }

        if let riskLine = riskSummary(answers: answers) {
            lines.append(riskLine)
        }

        let drawdownReaction = answers.singleValue(for: "drawdown_reaction")
        if !drawdownReaction.isEmpty {
            lines.append("During drawdowns: \(normalizedPhrase(drawdownReaction)).")
        }

        let experience = answers.singleValue(for: "experience_level")
        if !experience.isEmpty {
            lines.append("Experience: \(experience).")
        }

        let instruments = answers.multiValues(for: "comfortable_instruments")
        if !instruments.isEmpty {
            lines.append("Comfortable instruments: \(humanList(instruments, maxItems: 5)).")
        }

        let style = answers.singleValue(for: "portfolio_style")
        if !style.isEmpty {
            lines.append("Portfolio style: \(normalizedPhrase(style)).")
        }

        let rebalance = answers.singleValue(for: "rebalance_frequency")
        if !rebalance.isEmpty {
            lines.append("Rebalancing: \(normalizedPhrase(rebalance)).")
        }

        let avoid = answers.multiValues(for: "must_avoid").filter { $0 != "No strong exclusions" }
        if answers.multiValues(for: "must_avoid").contains("No strong exclusions") && avoid.isEmpty {
            lines.append("No strong hard exclusions.")
        } else if !avoid.isEmpty {
            lines.append("Avoid: \(humanList(avoid, maxItems: 4)).")
        }

        let preferred = answers.multiValues(for: "preferred_style")
        if !preferred.isEmpty {
            lines.append("Preferred style: \(humanList(preferred, maxItems: 4)).")
        }

        return lines
    }

    private static func riskSummary(answers: ReportMemoryQuizAnswers) -> String? {
        let selfAssessment = answers.singleValue(for: "risk_self_assessment")
        let maxDrawdown = answers.singleValue(for: "max_acceptable_drawdown")
        let horizon = answers.singleValue(for: "time_horizon")

        if selfAssessment == "Very aggressive", horizon == "15+ years" || maxDrawdown == "Any drawdown if thesis is intact and horizon is 10+ years" {
            return "Risk profile: very aggressive on a long horizon."
        }

        if selfAssessment == "Aggressive",
           maxDrawdown == "30–50%" || maxDrawdown == "Any drawdown if thesis is intact and horizon is 10+ years" {
            return "Risk profile: aggressive, comfortable with large drawdowns."
        }

        guard !selfAssessment.isEmpty else {
            return maxDrawdown.isEmpty ? nil : "Maximum acceptable drawdown: \(maxDrawdown)."
        }

        if maxDrawdown.isEmpty {
            return "Risk profile: \(selfAssessment.lowercased())."
        }
        return "Risk profile: \(selfAssessment.lowercased()); maximum acceptable drawdown: \(maxDrawdown)."
    }

    private static func humanList(_ values: [String], maxItems: Int) -> String {
        let unique = Array(NSOrderedSet(array: values)) as? [String] ?? values
        let trimmed = Array(unique.prefix(maxItems))
        guard !trimmed.isEmpty else { return "" }
        if unique.count > maxItems {
            return trimmed.joined(separator: ", ") + ", and others"
        }
        if trimmed.count == 1 {
            return trimmed[0]
        }
        if trimmed.count == 2 {
            return trimmed.joined(separator: " and ")
        }
        return trimmed.dropLast().joined(separator: ", ") + ", and " + (trimmed.last ?? "")
    }

    private static func makeSection(title: String, lines: [String]) -> String {
        let body = lines
            .map { clipSentence($0, maxLength: 180) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return "## \(title)\n\(body)"
    }

    private static func normalizedPhrase(_ text: String) -> String {
        let lowered = text.prefix(1).lowercased() + text.dropFirst()
        return lowered.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clipSentence(_ text: String, maxLength: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxLength else {
            return normalized
        }
        return String(normalized.prefix(maxLength - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
