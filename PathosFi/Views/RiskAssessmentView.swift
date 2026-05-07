import SwiftUI

struct RiskAssessmentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = RiskAssessmentViewModel()

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color("BackgroundTop"), Color("BackgroundBottom")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Header
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 60)

                        Text("PathosFi")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Invest with Mathematical Peace of Mind.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 40)

                    // MARK: Input Card
                    VStack(spacing: 28) {

                        // Starting Capital
                        InputSection(title: "Starting Capital", icon: "dollarsign.circle.fill") {
                            VStack(spacing: 12) {
                                Text(viewModel.formattedCapital)
                                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color("AccentGreen"))

                                NumericKeypadView(value: $viewModel.capitalInput,
                                                  displayValue: $viewModel.capitalRaw)
                            }
                        }

                        Divider().opacity(0.12)

                        // Time Horizon
                        InputSection(title: "Time Horizon", icon: "calendar.circle.fill") {
                            HStack(spacing: 8) {
                                ForEach(TimeHorizon.allCases) { horizon in
                                    TimeHorizonPill(
                                        label: horizon.rawValue,
                                        isSelected: viewModel.selectedHorizon == horizon
                                    ) {
                                        viewModel.selectedHorizon = horizon
                                    }
                                }
                            }
                        }

                        Divider().opacity(0.12)

                        // Sleep-at-Night Slider
                        InputSection(
                            title: "Sleep-at-Night Limit",
                            icon: "moon.zzz.fill",
                            subtitle: "Max % you can lose before you panic"
                        ) {
                            VStack(spacing: 16) {
                                HStack {
                                    Text("1%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(viewModel.maxLossPercent.safeInt(fallback: 15))%")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(viewModel.lossColor)
                                    Spacer()
                                    Text("50%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Slider(value: $viewModel.maxLossPercent, in: 1...50, step: 1)
                                    .tint(viewModel.lossColor)

                                Text(viewModel.lossDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }

                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 20)

                    // MARK: CTA Button
                    Button {
                        appState.riskProfile = RiskProfileInput(
                            startingCapital: viewModel.capitalRaw,
                            timeHorizon: viewModel.selectedHorizon,
                            maxLossPercent: viewModel.maxLossPercent
                        )
                        appState.navigateToDashboard()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Generate My Risk Profile")
                                .font(.system(size: 17, weight: .semibold))
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color("AccentGreen"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 50)
                }
            }
        }
    }
}

// MARK: - Sub-components

private struct InputSection<Content: View>: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color("AccentGreen"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content()
        }
    }
}

private struct TimeHorizonPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? .black : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? Color("AccentGreen")
                        : Color(.systemGray5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Numeric Keypad

struct NumericKeypadView: View {
    @Binding var value: String
    @Binding var displayValue: Double

    let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["K", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handleKey(key)
                        } label: {
                            Text(key)
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private func handleKey(_ key: String) {
        switch key {
        case "⌫":
            if !value.isEmpty { value.removeLast() }
        case "K":
            // Multiply current value by 1000
            if let current = Double(value), current > 0 {
                value = String((current * 1000).safeInt())
            }
        default:
            if value.count < 8 { value += key }
        }
        displayValue = Double(value) ?? 0
    }
}
