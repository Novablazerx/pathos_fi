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
                AuraBackground()

                ScrollView {
                    VStack(spacing: 16) {

                        // MARK: Projected Value (full-width bento)
                        ProjectedValueCard(
                            capital: appState.riskProfile.startingCapital,
                            simulationResult: viewModel.simulationResult
                        )

                        // MARK: Outcome Paths pie chart
                        ProbabilityPieCard(
                            result: viewModel.simulationResult,
                            isLoading: viewModel.isSimulating
                        )

                        // MARK: Bento stat grid
                        if let result = viewModel.simulationResult {
                            BentoStatGrid(
                                result: result,
                                maxLoss: appState.riskProfile.maxLossPercent
                            )
                        }

                        // MARK: CTA
                        Button {
                            appState.navigateToRecommendations()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Color.teal)
                                Text("Optimize AI Hedges")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Portfolio Aura")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        appState.navigateBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color.teal)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.runSimulation(profile: appState.riskProfile) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.teal)
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

// MARK: - Projected Value Card

private struct ProjectedValueCard: View {
    let capital: Double
    let simulationResult: SimulationResult?

    private var projectedValue: Double {
        let ret = simulationResult?.expectedReturn.safeValue() ?? 8.0
        return capital.safeValue() * (1 + ret / 100)
    }

    private var expectedReturnStr: String {
        let ret = simulationResult?.expectedReturn.safeValue() ?? 8.0
        return ret.safeSignedPercentString()
    }

    private var formattedProjected: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: projectedValue)) ?? "$\(projectedValue.safeInt())"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Ellipse()
                .fill(Color.teal.opacity(0.2))
                .blur(radius: 40)
                .frame(width: 160, height: 160)
                .offset(x: 20, y: -40)

            VStack(alignment: .leading, spacing: 10) {
                Text("PROJECTED VALUE (1 YR)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.teal.opacity(0.7))
                    .tracking(1.5)

                Text(formattedProjected)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12))
                    Text("\(expectedReturnStr) Expected trajectory")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.purple.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.15))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.purple.opacity(0.2), lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
        .padding(.horizontal, 16)
    }
}

// MARK: - Probability Pie Chart

struct ProbabilityPieCard: View {
    let result: SimulationResult?
    var isLoading: Bool = false
    var isGhost: Bool = false

    var slices: [PieSlice] {
        guard let r = result else {
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
            PieSlice(label: "Upside",               percent: r.upsidePercent.safeValue(),     color: .upside),
            PieSlice(label: "Acceptable Volatility", percent: r.acceptablePercent.safeValue(), color: .acceptable),
            PieSlice(label: "Tail Risk",             percent: r.tailRiskPercent.safeValue(),   color: .tailRisk),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("OUTCOME PATHS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1.5)
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
                    ProgressView().scaleEffect(0.8).tint(Color.teal)
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
            .frame(height: 200)
            .chartLegend(.hidden)
            .opacity(isLoading ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.6), value: result?.upsidePercent)

            VStack(spacing: 8) {
                ForEach(slices) { slice in
                    PieLegendRow(slice: slice)
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
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
                .frame(width: 10, height: 10)
            Text(slice.label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(slice.percent.safePercentString())
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(slice.color.textColor)
        }
    }
}

// MARK: - Bento Stat Grid

private struct BentoStatGrid: View {
    let result: SimulationResult
    let maxLoss: Double

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            BentoStatCard(title: "Value at Risk",  value: result.var95.safePercentString(),    subtitle: "95% Confidence",    color: Color.pink)
            BentoStatCard(title: "Win Rate",       value: "\(result.upsidePercent.safeInt())%", subtitle: "Positive outcomes", color: Color.teal)
            BentoStatCard(title: "Sharpe Ratio",   value: "1.45",                               subtitle: "Risk-adjusted",     color: Color.purple)
            BentoStatCard(title: "Max Drawdown",   value: "-\((maxLoss + 2).safeInt())%",        subtitle: "Simulated worst",   color: .white.opacity(0.9))
        }
        .padding(.horizontal, 16)
    }
}

struct BentoStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1)

            Text(value)
                .font(.system(size: 28, weight: .light, design: .rounded))
                .foregroundStyle(color)

            Text(subtitle.uppercased())
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 24)
    }
}

// MARK: - PieSliceColor extension

extension PieSliceColor {
    var color: Color {
        switch self {
        case .upside:     return Color.teal.opacity(0.85)
        case .acceptable: return Color.purple.opacity(0.75)
        case .tailRisk:   return Color.pink.opacity(0.85)
        }
    }

    var textColor: Color {
        switch self {
        case .upside:     return Color.teal
        case .acceptable: return Color.purple
        case .tailRisk:   return Color.pink
        }
    }
}
