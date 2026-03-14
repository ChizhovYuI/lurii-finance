import SwiftUI

struct AIContextSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var reportMemory = ""
    @State private var reportMemorySaveMessage: String?
    @State private var reportMemorySaveSucceeded: Bool?
    @State private var lastLoadedReportMemory = ""
    @State private var showReportMemoryQuiz = false
    @State private var isSavingReportMemory = false
    @FocusState private var reportMemoryFocused: Bool

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Context")
                    .font(.title)
                    .foregroundStyle(.primary)

                if viewModel.isLoading {
                    ProgressView("Loading...")
                } else if let errorMessage = viewModel.errorMessage {
                    EmptyStateView(title: "Settings unavailable", message: errorMessage, actionTitle: "Retry") {
                        viewModel.load()
                    }
                } else {
                    reportMemorySection
                }
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("AI Context")
        .onAppear {
            guard !isPreview else { return }
            viewModel.load()
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            if !isLoading {
                syncReportMemoryFromViewModel()
            }
        }
        .sheet(isPresented: $showReportMemoryQuiz) {
            ReportMemoryQuizSheet { generatedMemory in
                reportMemory = generatedMemory
                reportMemoryFocused = true
                reportMemorySaveSucceeded = true
                reportMemorySaveMessage = "Profile draft created. Review it and save when ready."
            }
        }
    }

    private var reportMemorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Report Context")
                        .font(.headline)
                    Text("Used in future weekly AI reports. Add stable context like location, income, goals, and risk profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(reportMemoryCharacterCount)/4000")
                    .font(.caption)
                    .foregroundStyle(reportMemoryCharacterCount > 4000 ? DesignTokens.error : .secondary)
            }

            HStack(spacing: 12) {
                Button("Create from Quiz") {
                    showReportMemoryQuiz = true
                }
                .buttonBorderShape(.capsule)
                .buttonStyle(.glass)
                .disabled(isSavingReportMemory)

                Button("Edit Manually") {
                    reportMemoryFocused = true
                }
                .buttonBorderShape(.capsule)
                .buttonStyle(.glass)
                .disabled(isSavingReportMemory)
            }

            ZStack(alignment: .topLeading) {
                if reportMemory.isEmpty {
                    Text(exampleReportMemoryPlaceholder)
                        .font(DesignTokens.bodyFont)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                }

                TextEditor(text: $reportMemory)
                    .font(DesignTokens.bodyFont)
                    .focused($reportMemoryFocused)
                    .frame(minHeight: 220)
                    .padding(4)
                    .onChange(of: reportMemory) { _, _ in
                        clearReportMemoryStatus()
                    }
            }
            .background(.white.opacity(0.5), in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                    .stroke(DesignTokens.border)
            )

            HStack(spacing: 12) {
                Button(isSavingReportMemory ? "Saving..." : "Save Context") {
                    saveReportMemory()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingReportMemory || reportMemoryCharacterCount > 4000)

                Button("Revert") {
                    reportMemory = lastLoadedReportMemory
                    clearReportMemoryStatus()
                }
                .buttonStyle(.bordered)
                .disabled(reportMemory == lastLoadedReportMemory || isSavingReportMemory)
            }

            if let reportMemorySaveMessage {
                Text(reportMemorySaveMessage)
                    .font(.caption)
                    .foregroundStyle(reportMemorySaveSucceeded == false ? DesignTokens.error : .secondary)
            }
        }
        .padding(DesignTokens.blockPadding)
        .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                .stroke(DesignTokens.border)
        )
    }

    private func saveReportMemory() {
        guard !isSavingReportMemory else { return }
        clearReportMemoryStatus()
        isSavingReportMemory = true

        Task {
            let success = await viewModel.saveAIReportMemory(reportMemory.trimmingCharacters(in: .whitespacesAndNewlines))
            isSavingReportMemory = false
            if success {
                lastLoadedReportMemory = viewModel.aiReportMemory
                reportMemory = viewModel.aiReportMemory
                reportMemorySaveSucceeded = true
                reportMemorySaveMessage = "Weekly report context saved."
            } else {
                reportMemorySaveSucceeded = false
                reportMemorySaveMessage = "Unable to save weekly report context."
            }
        }
    }

    private func syncReportMemoryFromViewModel(force: Bool = false) {
        let loaded = viewModel.aiReportMemory
        if force || reportMemory == lastLoadedReportMemory {
            reportMemory = loaded
        }
        lastLoadedReportMemory = loaded
    }

    private func clearReportMemoryStatus() {
        reportMemorySaveMessage = nil
        reportMemorySaveSucceeded = nil
    }

    private var reportMemoryCharacterCount: Int {
        reportMemory.count
    }

    private var exampleReportMemoryPlaceholder: String {
        """
        ## Location & Expenses
        Living in Thailand, non-resident / digital nomad.
        Expenses in THB, rent in Thailand, likely a UK mortgage.

        ## Income & Finances
        Salary: £5,000/month in GBP.
        Investing: £2,000/month.
        Living expenses: $2,500–5,000/month.
        Emergency fund: Wise + KBank (~$14,000).

        ## Investment Profile
        Goal: FIRE, horizon 7–15 years.
        Risk profile: aggressive, comfortable with drawdowns on a 10+ year horizon.
        Experience: 2–5 years.
        Instruments: ETFs, stocks, crypto, DeFi, occasional individual equities.
        Rebalancing: monthly.
        """
    }
}

#Preview {
    AIContextSettingsView()
}
