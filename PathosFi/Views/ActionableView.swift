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
        NavigationStack {
            ZStack {
                Color("BackgroundTop").ignoresSafeArea()

                if viewModel.isOptimising {
                    OptimisationLoadingView()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {

                            VaRConstraintBanner(maxLoss: appState.riskProfile.maxLossPercent)

                            if let ghostResult = viewModel.ghostSimulationResult {
                                ProbabilityPieCard(result: ghostResult, isGhost: true)
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
                    .animation(.easeInOut, value: viewModel.ghostSimulationResult != nil)
                }
            }
            .navigationTitle("Smart Pairs")
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
                    Label("\(appState.riskProfile.maxLossPercent.safeInt())% max loss",
                          systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(item: $viewModel.selectedPairForExecution) { pair in
                ExecuteConfirmationSheet(pair: pair)
            }
        }
        .task {
            await viewModel.loadRecommendations(profile: appState.riskProfile)
        }
    }
}

// MARK: - VaR Constraint Banner

private struct VaRConstraintBanner: View {
    let maxLoss: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Color("AccentGreen"))
            VStack(alignment: .leading, spacing: 2) {
                Text("95% VaR Constraint Active")
                    .font(.system(size: 13, weight: .semibold))
                Text("All pairs keep tail risk ≤ 5% of outcomes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(maxLoss.safeInt())%")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color("AccentGreen"))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}

// MARK: - Smart Pair Card

struct SmartPairCard: View {
    let pair: SmartPairModel
    var isSimulating: Bool = false
    let onSimulate: () -> Void
    let onExecute: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HedgeTypeBadge(hedgeType: pair.hedgeType)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color(.systemGray5), in: Circle())
                    }
                }

                Text(pair.name)
                    .font(.system(size: 17, weight: .bold))

                Text(pair.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            AllocationBar(
                primaryTicker: pair.primaryAsset.ticker,
                hedgeTicker: pair.hedgeAsset.ticker,
                primaryWeight: pair.primaryWeight.safeValue(),
                hedgeWeight: pair.hedgeWeight.safeValue()
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack(spacing: 0) {
                let safeReturn = pair.expectedReturn.safeValue()
                PairStat(
                    label: "Expected Return",
                    value: safeReturn.safeSignedPercentString(),
                    valueColor: safeReturn >= 0 ? Color("AccentGreen") : .red
                )
                Divider().frame(height: 40)
                PairStat(
                    label: "95% VaR",
                    value: pair.simulatedVaR95.safePercentString(),
                    valueColor: .orange
                )
                Divider().frame(height: 40)
                PairStat(
                    label: "Hedge Ratio",
                    value: "\((pair.hedgeWeight * 100).safeInt())%",
                    valueColor: .primary
                )
            }
            .padding(.top, 12)

            HStack(spacing: 10) {
                Button(action: onSimulate) {
                    HStack(spacing: 6) {
                        if isSimulating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                        }
                        Text("Simulate Pair")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(.primary)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isSimulating)

                Button(action: onExecute) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                        Text("Execute")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(.black)
                    .background(Color("AccentGreen"), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
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
                        .fill(Color("AccentGreen"))
                        .frame(width: geo.size.width * max(0, min(pw, 1.0)))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.7))
                        .frame(width: geo.size.width * max(0, min(hw, 1.0)))
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Label("\((primaryWeight * 100).safeInt())% \(primaryTicker)", systemImage: "square.fill")
                    .foregroundStyle(Color("AccentGreen"))
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
    var valueColor: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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
        case .putOption:  return .purple
        case .bond:       return .blue
        case .cash:       return .gray
        case .commodity:  return Color("AccentGreen")
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
                .tint(Color("AccentGreen"))

            Text("Running 10,000 simulations\(dots)")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text("Optimising hedge ratios to satisfy your 95% VaR constraint")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
            Text("Try increasing your maximum loss limit, or adjusting your time horizon.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color("AccentGreen"))

                Text(pair.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(pair.formattedWeights)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                Text("Brokerage integration would execute here.\nThis prototype shows the recommendation flow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Done") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.black)
                    .background(Color("AccentGreen"))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
            }
            .padding(.top, 40)
            .navigationTitle("Execute Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
