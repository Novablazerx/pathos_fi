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
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.027, blue: 0.063).ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Glowing check icon
                ZStack {
                    Ellipse()
                        .fill(Color.teal.opacity(0.25))
                        .blur(radius: 30)
                        .frame(width: 100, height: 100)
                    Circle()
                        .fill(.white.opacity(0.05))
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.teal)
                }

                Text(pair.name)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // Weights pill
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.purple)
                    Text(pair.formattedWeights)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))

                Text("Brokerage integration would execute here.\nThis prototype shows the recommendation flow.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button("Return to Dashboard") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
        }
    }
}

#Preview {
    ActionableView()
        .environmentObject(AppState())
        .modelContainer(for: [UserRiskProfile.self, SmartPair.self, UserInteraction.self], inMemory: true)
}
