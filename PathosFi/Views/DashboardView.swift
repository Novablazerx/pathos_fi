import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: DashboardViewModel

    init() {
        _viewModel = StateObject(wrappedValue: DashboardViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("BackgroundTop").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // MARK: Portfolio Header
                        PortfolioHeaderCard(
                            capital: appState.riskProfile.startingCapital,
                            simulationResult: viewModel.simulationResult
                        )

                        // MARK: Probability Pie Chart
                        ProbabilityPieCard(
                            result: viewModel.simulationResult,
                            isLoading: viewModel.isSimulating
                        )

                        // MARK: Risk Summary Stats
                        if let result = viewModel.simulationResult {
                            RiskStatGrid(
                                result: result,
                                maxLoss: appState.riskProfile.maxLossPercent,
                                capital: appState.riskProfile.startingCapital
                            )
                        }

                        // MARK: Navigate to Recommendations
                        Button {
                            appState.navigateToRecommendations()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                Text("View Smart Pair Recommendations")
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "arrow.right")
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color("AccentGreen"))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Portfolio Overview")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        appState.navigateBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color("AccentGreen"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.runSimulation(profile: appState.riskProfile) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color("AccentGreen"))
                    }
                    .disabled(viewModel.isSimulating)
                }
            }
        }
        .task {
            await viewModel.runSimulation(profile: appState.riskProfile)
        }
    }
}

// MARK: - Portfolio Header Card

private struct PortfolioHeaderCard: View {
    let capital: Double
    let simulationResult: SimulationResult?

    var body: some View {
        VStack(spacing: 4) {
            Text(formattedCapital)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if let result = simulationResult {
                let safeReturn = result.expectedReturn.safeValue()
                HStack(spacing: 4) {
                    Image(systemName: safeReturn >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("Expected: \(safeReturn.safeSignedPercentString())")
                        .font(.system(size: 15))
                }
                .foregroundStyle(safeReturn >= 0 ? Color("AccentGreen") : .red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private var formattedCapital: String {
        let safeCapital = capital.safeValue()
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: safeCapital)) ?? "$\(safeCapital.safeInt())"
    }
}

// MARK: - Probability Pie Chart (SectorMark)

struct ProbabilityPieCard: View {
    let result: SimulationResult?
    var isLoading: Bool = false
    var isGhost: Bool = false

    var slices: [PieSlice] {
        guard let r = result else {
            // Three sectors at all times so `SectorMark` count does not jump when `result` arrives.
            let a = 100.0 / 3.0
            let b = 100.0 / 3.0
            let c = 100.0 - a - b
            return [
                PieSlice(label: "Upside", percent: a, color: .upside),
                PieSlice(label: "Acceptable Volatility", percent: b, color: .acceptable),
                PieSlice(label: "Tail Risk", percent: c, color: .tailRisk),
            ]
        }
        return [
            PieSlice(label: "Upside",                percent: r.upsidePercent.safeValue(),     color: .upside),
            PieSlice(label: "Acceptable Volatility",  percent: r.acceptablePercent.safeValue(), color: .acceptable),
            PieSlice(label: "Tail Risk",              percent: r.tailRiskPercent.safeValue(),   color: .tailRisk),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Probability Distribution", systemImage: "chart.pie.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if isGhost {
                    Text("SIMULATED")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.7))
                        .clipShape(Capsule())
                }
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                }
            }

            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Probability", max(slice.percent.safeValue(fallback: 0), 0.001)),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(slice.color.color)
                .cornerRadius(4)
            }
            .frame(height: 220)
            .chartLegend(.hidden)
            .opacity(isLoading ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.6), value: result?.upsidePercent)

            // Custom Legend
            VStack(spacing: 8) {
                ForEach(slices) { slice in
                    PieLegendRow(slice: slice)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
        .opacity(isGhost ? 0.85 : 1.0)
    }
}

private struct PieLegendRow: View {
    let slice: PieSlice

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(slice.color.color)
                .frame(width: 12, height: 12)

            Text(slice.label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            Text(slice.percent.safePercentString())
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(slice.color.textColor)
        }
    }
}

// MARK: - Risk Stat Grid

private struct RiskStatGrid: View {
    let result: SimulationResult
    let maxLoss: Double
    let capital: Double

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: "95% VaR",
                value: result.var95.safePercentString(),
                subtitle: "Worst-case loss",
                valueColor: result.var95.safeValue() < -maxLoss.safeValue() ? .red : Color("AccentGreen")
            )
            StatCard(
                title: "Max Loss Limit",
                value: "\(maxLoss.safeInt())%",
                subtitle: "Your threshold",
                valueColor: .primary
            )
            StatCard(
                title: "Dollar at Risk",
                value: formatDollar(capital.safeValue() * abs(result.var95.safeValue()) / 100),
                subtitle: "At 95% confidence",
                valueColor: .orange
            )
            StatCard(
                title: "Constraint Met",
                value: result.tailRiskPercent.safeValue() <= 5 ? "✓ Yes" : "✗ No",
                subtitle: "Tail risk ≤ 5%",
                valueColor: result.tailRiskPercent.safeValue() <= 5 ? Color("AccentGreen") : .red
            )
        }
        .padding(.horizontal, 16)
    }

    private func formatDollar(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value.safeInt())"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - PieSliceColor extension

extension PieSliceColor {
    var color: Color {
        switch self {
        case .upside:     return Color("PieUpside")
        case .acceptable: return Color("PieAcceptable")
        case .tailRisk:   return Color("PieTailRisk")
        }
    }

    var textColor: Color {
        switch self {
        case .upside:     return .green
        case .acceptable: return .yellow
        case .tailRisk:   return .red
        }
    }
}
