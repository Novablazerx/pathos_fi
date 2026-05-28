import SwiftUI
import SwiftData
import Combine

struct ActionableView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ActionableViewModel
    @Environment(\.modelContext) private var modelContext

    init() {
        _viewModel = StateObject(wrappedValue: ActionableViewModel())
    }

    var body: some View {
        ZStack {
            AuraBackground()

            VStack(spacing: 0) {
                ActionableHeaderView(onBack: { appState.navigateBack() })

                if viewModel.isOptimising {
                    OptimisationLoadingView()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {

                            AuraConstraintBanner(maxLoss: appState.riskProfile.maxLossPercent)

                            if let rationale = viewModel.rlRationale {
                                RLRationaleBanner(rationale: rationale, status: viewModel.rlStatus)
                            }

                            // Ghost simulation progress card
                            if viewModel.simulatingPairId != nil {
                                SynthesisProgressCard()
                                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                            }

                            if let ghostResult = viewModel.ghostSimulationResult {
                                ProbabilityPieCard(
                                    result: ghostResult,
                                    isGhost: true,
                                    capital: appState.riskProfile.startingCapital,
                                    maxLossPercent: appState.riskProfile.maxLossPercent
                                )
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                            }

                            ForEach(viewModel.smartPairs) { pair in
                                SmartPairCard(
                                    pair: pair,
                                    isSimulating: viewModel.simulatingPairId == pair.id
                                ) {
                                    Task {
                                        await viewModel.simulatePair(pair, profile: appState.riskProfile)
                                        viewModel.recordInteraction(
                                            pairId: pair.id, action: "simulate",
                                            hedgeType: pair.hedgeType, context: modelContext
                                        )
                                    }
                                } onExecute: {
                                    viewModel.recordInteraction(
                                        pairId: pair.id, action: "execute",
                                        hedgeType: pair.hedgeType, context: modelContext
                                    )
                                    viewModel.selectedPairForExecution = pair
                                } onDismiss: {
                                    viewModel.recordInteraction(
                                        pairId: pair.id, action: "dismiss",
                                        hedgeType: pair.hedgeType, context: modelContext
                                    )
                                    viewModel.dismiss(pair: pair)
                                }
                            }

                            if viewModel.smartPairs.isEmpty {
                                NoPairsView()
                            }

                            Spacer(minLength: 40)
                        }
                        .padding(.top, 8)
                    }
                    .animation(.easeInOut, value: viewModel.simulatingPairId != nil)
                }
            }
        }
        .sheet(item: $viewModel.selectedPairForExecution) { pair in
            ExecuteConfirmationSheet(pair: pair)
                .environmentObject(appState)
        }
        .task {
            await viewModel.loadRecommendations(
                profile: appState.riskProfile,
                userId: appState.currentUser?.userId,
                portfolioValue: appState.portfolioValue
            )
        }
    }
}

// MARK: - Actionable Header

private struct ActionableHeaderView: View {
    let onBack: () -> Void

    private var backButton: some View {
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
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("OPTIMIZATION")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.purple.opacity(0.8))
                .tracking(2)
            Text("AI Hedges")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.leading, 12)
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.teal)
            Text("LIVE")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.teal)
                .tracking(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.teal.opacity(0.5), lineWidth: 1))
    }

    var body: some View {
        HStack(alignment: .center) {
            backButton
            titleSection
            Spacer()
            liveBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Aura Constraint Banner

private struct AuraConstraintBanner: View {
    let maxLoss: Double

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(Color.teal)
                    .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Aura Constraint Active")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Optimizing to keep max loss below \(maxLoss.safeInt())%")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.12), Color.teal.opacity(0.12)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 16)
    }
}

// MARK: - RL Rationale Banner

private struct RLRationaleBanner: View {
    let rationale: String
    let status: BackendAPIClient.RLStatus?

    private var isApproved: Bool { status == .approved }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((isApproved ? Color.green : Color.orange).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: isApproved ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isApproved ? Color.green : Color.orange)
                    .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isApproved ? "Plan Approved" : "Fallback: Hold All")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(rationale)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 16)
    }
}

// MARK: - Synthesis Progress Card

private struct SynthesisProgressCard: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hexagon.fill")
                    .foregroundStyle(Color.teal)
                    .font(.system(size: 14))
                    .rotationEffect(.degrees(progress * 360))
                    .animation(.linear(duration: 3), value: progress)
                Text("Synthesizing Hedge Scenario...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.teal)
            }

            GeometryReader { geo in
                Capsule()
                    .fill(.white.opacity(0.05))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.8), Color.teal.opacity(0.8)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress)
                    }
            }
            .frame(height: 6)
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
        .padding(.horizontal, 16)
        .onAppear {
            withAnimation(.easeInOut(duration: 3)) {
                progress = 1.0
            }
        }
    }
}

// MARK: - Smart Pair Card

struct SmartPairCard: View {
    let pair: SmartPairModel
    var isSimulating: Bool = false
    let onSimulate: () -> Void
    let onExecute: () -> Void
    let onDismiss: () -> Void

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HedgeTypeBadge(hedgeType: pair.hedgeType)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(6)
                        .background(.white.opacity(0.05), in: Circle())
                }
            }

            HStack(alignment: .top) {
                pairInfo
                Spacer()
                auraBoost
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var pairInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pair.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 8) {
                Text("\((pair.primaryWeight * 100).safeInt())% \(pair.primaryAsset.ticker)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.05))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))

                Text("+\((pair.hedgeWeight * 100).safeInt())% \(pair.hedgeAsset.ticker)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.teal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.teal.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.teal.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private var auraBoost: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("AURA BOOST")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.8)
            Text(pair.expectedReturn.safeSignedPercentString())
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.purple.opacity(0.9))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            let safeReturn = pair.expectedReturn.safeValue()
            PairStat(label: "Expected Return", value: safeReturn.safeSignedPercentString(),
                     valueColor: safeReturn >= 0 ? Color.teal : .red)
            Divider().frame(height: 36).overlay(Color.white.opacity(0.1))
            PairStat(label: "95% VaR", value: pair.simulatedVaR95.safePercentString(), valueColor: .orange)
            Divider().frame(height: 36).overlay(Color.white.opacity(0.1))
            PairStat(label: "Hedge Ratio", value: "\((pair.hedgeWeight * 100).safeInt())%", valueColor: .white.opacity(0.8))
        }
        .padding(.bottom, 4)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onSimulate) {
                HStack(spacing: 6) {
                    if isSimulating {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "eye")
                            .font(.system(size: 13))
                    }
                    Text("Preview")
                        .font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(.white.opacity(0.85))
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
            }
            .disabled(isSimulating)

            Button(action: onExecute) {
                Text("Execute")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
        .padding(16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            AllocationBar(
                primaryTicker: pair.primaryAsset.ticker,
                hedgeTicker: pair.hedgeAsset.ticker,
                primaryWeight: pair.primaryWeight.safeValue(),
                hedgeWeight: pair.hedgeWeight.safeValue()
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            statsRow
            actionButtons
        }
        .glassCard(cornerRadius: 32)
        .padding(.horizontal, 16)
    }
}

// MARK: - Allocation Bar

private struct AllocationBar: View {
    let primaryTicker: String
    let hedgeTicker: String
    let primaryWeight: Double
    let hedgeWeight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let pw = primaryWeight.safeValue(fallback: 0)
                let hw = hedgeWeight.safeValue(fallback: 0)
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.teal.opacity(0.8))
                        .frame(width: geo.size.width * max(0, min(pw, 1.0)))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: geo.size.width * max(0, min(hw, 1.0)))
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Label("\((primaryWeight * 100).safeInt())% \(primaryTicker)", systemImage: "square.fill")
                    .foregroundStyle(Color.teal)
                    .font(.caption)
                Spacer()
                Label("\((hedgeWeight * 100).safeInt())% \(hedgeTicker)", systemImage: "square.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Pair Stat

private struct PairStat: View {
    let label: String
    let value: String
    var valueColor: Color = .white

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Hedge Type Badge

private struct HedgeTypeBadge: View {
    let hedgeType: HedgeType

    var body: some View {
        Text(hedgeType.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.15), in: Capsule())
    }

    var badgeColor: Color {
        switch hedgeType {
        case .inverseETF: return .orange
        case .putOption:  return Color.purple
        case .callOption: return Color.green
        case .bond:       return .blue
        case .cash:       return .gray
        case .commodity:  return Color.teal
        }
    }
}

// MARK: - Optimisation Loading

private struct OptimisationLoadingView: View {
    @State private var dots = ""
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.teal)

            Text("Running 10,000 simulations\(dots)")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()

            Text("Optimising hedge ratios to satisfy your 95% VaR constraint")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .onReceive(timer) { _ in
            dots = dots.count < 3 ? dots + "." : ""
        }
    }
}

// MARK: - No Pairs View

private struct NoPairsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("No pairs satisfy your constraint")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Text("Try increasing your maximum loss limit, or adjusting your time horizon.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 60)
    }
}

// MARK: - Execute Confirmation Sheet

struct ExecuteConfirmationSheet: View {
    let pair: SmartPairModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        if let execution = pair.tradeExecution {
            SmartTradeSheet(pair: pair, execution: execution)
        } else {
            // Fallback for non-RL (OptimisationEngine) pairs
            StaticBrokerageSheet(pair: pair)
        }
    }
}

// MARK: - Static Brokerage Sheet (OptimisationEngine fallback)

private struct StaticBrokerageSheet: View {
    let pair: SmartPairModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.027, blue: 0.063).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                ZStack {
                    Ellipse()
                        .fill(Color.teal.opacity(0.25)).blur(radius: 30)
                        .frame(width: 100, height: 100)
                    Circle()
                        .fill(.white.opacity(0.05))
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32)).foregroundStyle(Color.teal)
                }
                Text(pair.name)
                    .font(.system(size: 22, weight: .light)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color.purple)
                    Text(pair.formattedWeights)
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.white.opacity(0.05)).clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
                Text("Brokerage integration would execute here.\nThis prototype shows the recommendation flow.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Spacer()
                Button("Return to Dashboard") { dismiss() }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                    .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 28))
                    .padding(.horizontal, 24)
                Spacer(minLength: 24)
            }
        }
    }
}

// MARK: - Smart Trade Sheet (RL trade execution)

private struct SmartTradeSheet: View {
    let pair: SmartPairModel
    let execution: TradeExecutionInfo

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    enum Phase { case confirm, executing, done }
    @State private var phase: Phase = .confirm
    @State private var outcome: TradeOutcome? = nil
    @State private var errorMessage: String? = nil

    private let currencyFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f
    }()

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.027, blue: 0.063).ignoresSafeArea()
            switch phase {
            case .confirm:  confirmView
            case .executing: executingView
            case .done:     doneView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    // MARK: Confirm phase

    private var confirmView: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(0.15)).frame(width: 36, height: 4)
                .padding(.top, 14).padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 20) {
                    // Icon + title
                    VStack(spacing: 12) {
                        ZStack {
                            Ellipse()
                                .fill(accentColor.opacity(0.20)).blur(radius: 24)
                                .frame(width: 80, height: 80)
                            Circle()
                                .fill(.white.opacity(0.05))
                                .overlay(Circle().stroke(accentColor.opacity(0.3), lineWidth: 1))
                                .frame(width: 60, height: 60)
                            Image(systemName: actionIcon)
                                .font(.system(size: 26)).foregroundStyle(accentColor)
                        }
                        Text(pair.name)
                            .font(.system(size: 24, weight: .light)).foregroundStyle(.white)
                    }
                    .padding(.bottom, 4)

                    // Trade detail card
                    tradeDetailCard
                        .padding(.horizontal, 20)

                    // Insufficient funds warning
                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(err).font(.caption).foregroundStyle(.orange.opacity(0.9))
                        }
                        .padding(12)
                        .background(.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                    }

                    // Confirm button
                    Button { triggerExecution() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(confirmButtonLabel)
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(errorMessage == nil ? accentColor : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(errorMessage != nil)
                    .padding(.horizontal, 20)

                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 8)
                }
            }
        }
        .onAppear { validateTrade() }
    }

    // MARK: Executing phase

    private var executingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().scaleEffect(1.5).tint(accentColor)
            Text("Executing trade…")
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
    }

    // MARK: Done phase

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Ellipse()
                    .fill(accentColor.opacity(0.22)).blur(radius: 28)
                    .frame(width: 100, height: 100)
                Circle()
                    .fill(.white.opacity(0.05))
                    .overlay(Circle().stroke(accentColor.opacity(0.3), lineWidth: 1))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32)).foregroundStyle(accentColor)
            }

            Text(doneTitle).font(.system(size: 22, weight: .light)).foregroundStyle(.white)

            if let o = outcome {
                outcomeCard(o).padding(.horizontal, 24)
            }

            Spacer()

            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity).frame(height: 56)
                .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 28))
                .padding(.horizontal, 24)

            Spacer(minLength: 24)
        }
    }

    // MARK: - Trade detail card (confirm phase)

    @ViewBuilder
    private var tradeDetailCard: some View {
        switch execution.action {

        case .buyEquity(let shares, let notionalUsd):
            let pricePerShare = notionalUsd / max(shares, 0.001)
            let cashAfter = (appState.currentUser?.cashBalance ?? 0) - notionalUsd
            detailRows([
                ("Action", "Buy \(execution.ticker)", Color.teal),
                ("Shares", String(format: "%.4g", shares), .white),
                ("Price / share", currencyFmt.string(from: NSNumber(value: pricePerShare)) ?? "", .white),
                ("Total cost", currencyFmt.string(from: NSNumber(value: notionalUsd)) ?? "", .orange),
                ("Cash after", currencyFmt.string(from: NSNumber(value: cashAfter)) ?? "", cashAfter >= 0 ? .white : .red),
            ])

        case .sellEquity(let shares, let notionalUsd):
            let holding = appState.holdings.first { $0.asset.ticker == execution.ticker }
            let pricePerShare = holding.map { $0.currentPrice } ?? (notionalUsd / max(shares, 0.001))
            let actualShares = min(shares, holding?.shares ?? 0)
            let proceeds = actualShares * pricePerShare
            let cashAfter = (appState.currentUser?.cashBalance ?? 0) + proceeds
            detailRows([
                ("Action", "Sell \(execution.ticker)", Color.pink),
                ("Shares", String(format: "%.4g", actualShares), .white),
                ("Price / share", currencyFmt.string(from: NSNumber(value: pricePerShare)) ?? "", .white),
                ("Proceeds", currencyFmt.string(from: NSNumber(value: proceeds)) ?? "", Color.teal),
                ("Cash after", currencyFmt.string(from: NSNumber(value: cashAfter)) ?? "", .white),
            ])

        case .buyOption(let isCall, let contracts, let strike, let expiry, let premPerContract, let totalPremium):
            let cashAfter = (appState.currentUser?.cashBalance ?? 0) - totalPremium
            detailRows([
                ("Type", "\(isCall ? "Call" : "Put") Option", isCall ? Color.green : Color.purple),
                ("Underlying", execution.ticker, .white),
                ("Strike", currencyFmt.string(from: NSNumber(value: strike)) ?? "", .white),
                ("Expiry", expiry, .white),
                ("Contracts", "\(contracts) × 100 shares", .white),
                ("Premium", "\(currencyFmt.string(from: NSNumber(value: premPerContract)) ?? "") / contract", .orange),
                ("Total cost", currencyFmt.string(from: NSNumber(value: totalPremium)) ?? "", .orange),
                ("Cash after", currencyFmt.string(from: NSNumber(value: cashAfter)) ?? "", cashAfter >= 0 ? .white : .red),
            ])
        }
    }

    private func detailRows(_ rows: [(String, String, Color)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack {
                    Text(row.0)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(row.1)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(row.2)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                if idx < rows.count - 1 {
                    Divider().background(.white.opacity(0.07))
                }
            }
        }
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Outcome card (done phase)

    @ViewBuilder
    private func outcomeCard(_ o: TradeOutcome) -> some View {
        let cashDelta = o.cashAfter - o.cashBefore
        VStack(spacing: 0) {
            ForEach(Array(o.summaryRows.enumerated()), id: \.offset) { idx, row in
                HStack {
                    Text(row.label)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(row.value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(row.valueColor)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                if idx < o.summaryRows.count - 1 {
                    Divider().background(.white.opacity(0.07))
                }
            }
            Divider().background(.white.opacity(0.07))
            HStack {
                Text("Cash change")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(cashDelta >= 0 ? "+" : "")\(currencyFmt.string(from: NSNumber(value: cashDelta)) ?? "")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(cashDelta >= 0 ? Color.teal : .red)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().background(.white.opacity(0.07))
            HStack {
                Text("Cash balance")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(currencyFmt.string(from: NSNumber(value: o.cashAfter)) ?? "")
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(accentColor)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Helpers

    private var accentColor: Color {
        switch execution.action {
        case .buyEquity:  return Color.teal
        case .sellEquity: return Color.pink
        case .buyOption(let isCall, _, _, _, _, _): return isCall ? Color.green : Color.purple
        }
    }

    private var actionIcon: String {
        switch execution.action {
        case .buyEquity:  return "arrow.up.circle.fill"
        case .sellEquity: return "arrow.down.circle.fill"
        case .buyOption(let isCall, _, _, _, _, _): return isCall ? "chart.line.uptrend.xyaxis.circle.fill" : "shield.lefthalf.filled"
        }
    }

    private var confirmButtonLabel: String {
        switch execution.action {
        case .buyEquity:  return "Confirm Purchase"
        case .sellEquity: return "Confirm Sale"
        case .buyOption:  return "Confirm Hedge"
        }
    }

    private var doneTitle: String {
        switch execution.action {
        case .buyEquity:  return "Purchased \(execution.ticker)"
        case .sellEquity: return "Sold \(execution.ticker)"
        case .buyOption(let isCall, _, _, _, _, _): return "\(isCall ? "Call" : "Put") Hedge Added"
        }
    }

    // MARK: - Validation

    private func validateTrade() {
        let cash = appState.currentUser?.cashBalance ?? 0
        switch execution.action {
        case .buyEquity(_, let notional):
            if cash < notional {
                errorMessage = "Insufficient cash. Need \(currencyFmt.string(from: NSNumber(value: notional)) ?? "") but have \(currencyFmt.string(from: NSNumber(value: cash)) ?? "")."
            }
        case .sellEquity(let shares, _):
            let held = appState.holdings.first { $0.asset.ticker == execution.ticker }?.shares ?? 0
            if held <= 0 {
                errorMessage = "\(execution.ticker) is not in your portfolio."
            } else if held < shares {
                // Partial sell is fine — we'll sell whatever is held
                errorMessage = nil
            }
        case .buyOption(_, _, _, _, _, let totalPremium):
            if cash < totalPremium {
                errorMessage = "Insufficient cash. Need \(currencyFmt.string(from: NSNumber(value: totalPremium)) ?? "") but have \(currencyFmt.string(from: NSNumber(value: cash)) ?? "")."
            }
        }
    }

    // MARK: - Execution dispatch

    private func triggerExecution() {
        phase = .executing
        Task {
            switch execution.action {
            case .buyEquity(let shares, let notionalUsd):
                outcome = await executeBuy(ticker: execution.ticker, shares: shares, notionalUsd: notionalUsd)
            case .sellEquity(let shares, _):
                outcome = await executeSell(ticker: execution.ticker, requestedShares: shares)
            case .buyOption(let isCall, let contracts, let strike, let expiry, let premPerContract, let totalPremium):
                outcome = await executeOptionBuy(
                    ticker: execution.ticker, isCall: isCall, contracts: contracts,
                    strike: strike, expiry: expiry,
                    premiumPerContract: premPerContract, totalPremium: totalPremium
                )
            }
            withAnimation { phase = .done }
        }
    }

    // MARK: - Equity buy

    @MainActor
    private func executeBuy(ticker: String, shares: Double, notionalUsd: Double) async -> TradeOutcome {
        let cashBefore = appState.currentUser?.cashBalance ?? 0
        let price = notionalUsd / max(shares, 0.001)

        if let idx = appState.holdings.firstIndex(where: { $0.asset.ticker == ticker }) {
            let old = appState.holdings[idx]
            let newShares  = old.shares + shares
            let newAvgCost = (old.shares * old.avgCost + shares * price) / newShares
            appState.holdings[idx] = HeldAsset(asset: old.asset, shares: newShares,
                                               avgCost: newAvgCost, currentPrice: old.currentPrice)
        } else {
            let asset = appState.backendAssets.first(where: { $0.ticker == ticker })
                     ?? OptimisationEngine.assetLibrary[ticker]
                     ?? AssetInfo(ticker: ticker, name: ticker,
                                  annualReturn: 0, annualVolatility: 0.20, category: .equity)
            appState.holdings.append(HeldAsset(asset: asset, shares: shares,
                                               avgCost: price, currentPrice: price))
        }
        appState.adjustCashBalance(by: -notionalUsd)

        if let assetId = appState.assetIdByTicker[ticker],
           let userId  = appState.currentUser?.userId,
           let holding = appState.holdings.first(where: { $0.asset.ticker == ticker }) {
            Task { try? await appState.apiClient.upsertUserAsset(
                userId: userId, assetId: assetId,
                quantity: holding.shares, avgCostBasis: holding.avgCost) }
        }

        let newHolding = appState.holdings.first(where: { $0.asset.ticker == ticker })
        return TradeOutcome(summaryRows: [
            .init(label: "Bought", value: "\(String(format: "%.4g", shares)) \(ticker)", valueColor: Color.teal),
            .init(label: "Price / share", value: currencyFmt.string(from: NSNumber(value: price)) ?? "", valueColor: .white),
            .init(label: "New position", value: "\(String(format: "%.4g", newHolding?.shares ?? shares)) shares", valueColor: .white),
        ], cashBefore: cashBefore, cashAfter: appState.currentUser?.cashBalance ?? 0)
    }

    // MARK: - Equity sell

    @MainActor
    private func executeSell(ticker: String, requestedShares: Double) async -> TradeOutcome {
        let cashBefore = appState.currentUser?.cashBalance ?? 0
        guard let idx = appState.holdings.firstIndex(where: { $0.asset.ticker == ticker }) else {
            return TradeOutcome(summaryRows: [
                .init(label: "Status", value: "No position found", valueColor: .orange)
            ], cashBefore: cashBefore, cashAfter: cashBefore)
        }
        let old = appState.holdings[idx]
        let sharesToSell = min(requestedShares, old.shares)
        let price    = old.currentPrice
        let proceeds = sharesToSell * price
        let remaining = old.shares - sharesToSell

        guard let assetId = appState.assetIdByTicker[ticker],
              let userId  = appState.currentUser?.userId else {
            return TradeOutcome(summaryRows: [], cashBefore: cashBefore, cashAfter: cashBefore)
        }

        if remaining <= 0 {
            appState.holdings.remove(at: idx)
            appState.adjustCashBalance(by: proceeds)
            Task { try? await appState.apiClient.deleteUserAsset(userId: userId, assetId: assetId) }
        } else {
            appState.holdings[idx] = HeldAsset(asset: old.asset, shares: remaining,
                                               avgCost: old.avgCost, currentPrice: old.currentPrice)
            appState.adjustCashBalance(by: proceeds)
            Task { try? await appState.apiClient.upsertUserAsset(
                userId: userId, assetId: assetId, quantity: remaining, avgCostBasis: old.avgCost) }
        }

        return TradeOutcome(summaryRows: [
            .init(label: "Sold", value: "\(String(format: "%.4g", sharesToSell)) \(ticker)", valueColor: Color.pink),
            .init(label: "Price / share", value: currencyFmt.string(from: NSNumber(value: price)) ?? "", valueColor: .white),
            .init(label: "Proceeds", value: currencyFmt.string(from: NSNumber(value: proceeds)) ?? "", valueColor: Color.teal),
            .init(label: "Remaining position", value: remaining > 0 ? "\(String(format: "%.4g", remaining)) shares" : "Position closed", valueColor: .white),
        ], cashBefore: cashBefore, cashAfter: appState.currentUser?.cashBalance ?? 0)
    }

    // MARK: - Option buy

    @MainActor
    private func executeOptionBuy(ticker: String, isCall: Bool, contracts: Int,
                                   strike: Double, expiry: String,
                                   premiumPerContract: Double, totalPremium: Double) async -> TradeOutcome {
        let cashBefore = appState.currentUser?.cashBalance ?? 0

        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        isoFmt.timeZone = TimeZone(abbreviation: "UTC")
        let expiryDate = isoFmt.date(from: expiry) ?? Date().addingTimeInterval(30 * 86400)

        var optionId: Int? = nil
        if let assetId = appState.assetIdByTicker[ticker] {
            let chain = (try? await appState.apiClient.fetchAllAssetOptions(assetId: assetId)) ?? []
            let optType = isCall ? "call" : "put"
            optionId = chain.first(where: {
                guard let t = $0.optionType, let s = $0.strikePrice, let e = $0.expiryDate else { return false }
                return t.lowercased() == optType && abs(s - strike) < 0.01 && e == expiry
            })?.optionId
        }

        let newContract = OptionsContract(
            optionId: optionId,
            underlyingTicker: ticker,
            type: isCall ? .call : .put,
            strikePrice: strike,
            expiryDate: expiryDate,
            contracts: contracts,
            costBasis: premiumPerContract,
            currentValue: premiumPerContract
        )

        var arr = appState.optionsByTicker[ticker] ?? []
        if let matchId = optionId, let idx = arr.firstIndex(where: { $0.optionId == matchId }) {
            let existing = arr[idx]
            let total = existing.contracts + contracts
            arr[idx] = OptionsContract(optionId: matchId, underlyingTicker: ticker,
                                       type: newContract.type, strikePrice: strike,
                                       expiryDate: expiryDate, contracts: total,
                                       costBasis: premiumPerContract, currentValue: premiumPerContract)
        } else {
            arr.append(newContract)
        }
        appState.optionsByTicker[ticker] = arr
        appState.adjustCashBalance(by: -totalPremium)

        if let optId = optionId, let userId = appState.currentUser?.userId {
            let total = arr.first(where: { $0.optionId == optId })?.contracts ?? contracts
            Task { try? await appState.apiClient.upsertUserOption(userId: userId, optionId: optId, contractsHeld: total) }
        }

        let displayExpiry = isoFmt.string(from: expiryDate)
        return TradeOutcome(summaryRows: [
            .init(label: "\(isCall ? "Call" : "Put") contracts added", value: "\(contracts) × \(ticker)", valueColor: isCall ? Color.green : Color.purple),
            .init(label: "Strike", value: currencyFmt.string(from: NSNumber(value: strike)) ?? "", valueColor: .white),
            .init(label: "Expiry", value: displayExpiry, valueColor: .white),
            .init(label: "Total premium", value: currencyFmt.string(from: NSNumber(value: totalPremium)) ?? "", valueColor: .orange),
        ], cashBefore: cashBefore, cashAfter: appState.currentUser?.cashBalance ?? 0)
    }
}

// MARK: - Trade Outcome

private struct TradeOutcome {
    struct Row { let label: String; let value: String; let valueColor: Color }
    let summaryRows: [Row]
    let cashBefore: Double
    let cashAfter: Double
}

#Preview {
    ActionableView()
        .environmentObject(AppState())
        .modelContainer(for: [UserRiskProfile.self, SmartPair.self, UserInteraction.self], inMemory: true)
}
