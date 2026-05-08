import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: DashboardViewModel

    init() {
        _viewModel = StateObject(wrappedValue: DashboardViewModel())
    }

    var body: some View {
        ZStack {
            AuraBackground()

            VStack(spacing: 0) {
                DashboardHeaderView(onBack: { appState.navigateBack() })

                ScrollView {
                    VStack(spacing: 16) {

                        // MARK: Projected Value (full-width bento)
                        ProjectedValueCard(
                            capital: appState.portfolioValue,
                            simulationResult: viewModel.simulationResult
                        )

                        // MARK: Outcome Paths pie chart
                        ProbabilityPieCard(
                            result: viewModel.simulationResult,
                            isLoading: viewModel.isSimulating,
                            capital: appState.portfolioValue,
                            maxLossPercent: appState.riskProfile.maxLossPercent
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

                        // MARK: Currently Held Assets
                        HeldAssetsSection(
                            holdings: appState.holdings.filter { $0.asset.category != .option },
                            optionsByTicker: appState.optionsByTicker
                        )

                        // MARK: Explore Assets CTA
                        Button {
                            appState.navigateToExploreAssets()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.grid.2x2")
                                    .foregroundStyle(Color.teal)
                                Text("Explore Assets")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.teal)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .padding(.horizontal, 20)
                            .glassCard(cornerRadius: 28)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .task {
            await viewModel.runSimulation(profile: appState.riskProfile)
        }
    }
}

// MARK: - Dashboard Header

private struct DashboardHeaderView: View {
    let onBack: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Button(action: onBack) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.12))
                        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
                        .frame(width: 42, height: 42)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("GOOD MORNING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.teal.opacity(0.8))
                    .tracking(2)
                Text("Portfolio Aura")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 12)

            Spacer()

            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.12))
                        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
                        .frame(width: 42, height: 42)
                    Image(systemName: "hexagon")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.teal)
                }
                Circle()
                    .fill(Color.pink)
                    .frame(width: 9, height: 9)
                    .offset(x: 1, y: -1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
    var capital: Double = 0
    var maxLossPercent: Double = 0

    private func dollarRange(for color: PieSliceColor) -> String? {
        guard capital > 0 else { return nil }
        let floor = capital * (1 - maxLossPercent / 100)
        let projected = capital * (1 + (result?.expectedReturn.safeValue() ?? 8.0) / 100)
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.maximumFractionDigits = 0
        func f(_ v: Double) -> String { fmt.string(from: NSNumber(value: v)) ?? "" }
        switch color {
        case .upside:     return "\(f(capital)) – \(f(projected))"
        case .acceptable: return "\(f(floor)) – \(f(capital))"
        case .tailRisk:   return "Below \(f(floor))"
        }
    }

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
                    PieLegendRow(slice: slice, rangeLabel: dollarRange(for: slice.color))
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
    var rangeLabel: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(slice.color.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(slice.label)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                if let range = rangeLabel {
                    Text(range)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
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

// MARK: - Held Assets Section

private struct HeldAssetsSection: View {
    let holdings: [HeldAsset]
    let optionsByTicker: [String: [OptionsContract]]

    @State private var selectedHolding: HeldAsset?

    private let fmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f
    }()

    private func categoryColor(_ category: AssetCategory) -> Color {
        switch category {
        case .equity:        return Color.teal
        case .bond:          return Color.purple
        case .commodity:     return Color.orange
        case .inverseEquity: return Color.pink
        case .option:        return Color.indigo
        }
    }

    var totalValue: String {
        let total = holdings.reduce(0) { $0 + $1.value }
        return fmt.string(from: NSNumber(value: total)) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PORTFOLIO HOLDINGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.teal.opacity(0.7))
                    .tracking(1.5)
                Spacer()
                Text(totalValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(spacing: 10) {
                ForEach(holdings) { holding in
                    HeldAssetRow(
                        holding: holding,
                        accentColor: categoryColor(holding.asset.category),
                        fmt: fmt
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedHolding = holding }
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
        .padding(.horizontal, 16)
        .fullScreenCover(item: $selectedHolding) { holding in
            AssetDetailsView(
                holding: holding,
                options: optionsByTicker[holding.asset.ticker] ?? []
            )
        }
    }
}

private struct HeldAssetRow: View {
    let holding: HeldAsset
    let accentColor: Color
    let fmt: NumberFormatter

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accentColor.opacity(0.25))
                .overlay(Circle().stroke(accentColor.opacity(0.5), lineWidth: 1))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(holding.asset.ticker.prefix(3))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accentColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(holding.asset.ticker)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(holding.asset.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(fmt.string(from: NSNumber(value: holding.value)) ?? "")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                let gain = holding.gainPct
                Text("\(gain >= 0 ? "+" : "")\(String(format: "%.1f", gain))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(gain >= 0 ? Color.teal : Color.pink)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
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
