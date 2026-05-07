import SwiftUI

struct RiskAssessmentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = RiskAssessmentViewModel()

    var body: some View {
        ZStack {
            AuraBackground()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {

                        // MARK: Mascot
                        MascotView()
                            .padding(.top, 60)
                            .padding(.bottom, 24)

                        // MARK: Header
                        VStack(spacing: 6) {
                            Text("PathosFi")
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundStyle(.clear)
                                .overlay(
                                    LinearGradient(
                                        colors: [.teal, .white, Color.purple.opacity(0.9)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .mask(
                                        Text("PathosFi")
                                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                                    )
                                )

                            Text("Invest with Mathematical Peace of Mind.")
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .tracking(0.3)
                        }
                        .padding(.bottom, 32)

                        // MARK: Input Card
                        VStack(spacing: 0) {

                            // Starting Capital
                            VStack(spacing: 10) {
                                Text("STARTING CAPITAL")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.teal.opacity(0.7))
                                    .tracking(2)

                                Text(viewModel.formattedCapital)
                                    .font(.system(size: 48, weight: .light, design: .rounded))
                                    .foregroundStyle(Color.teal)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                            }
                            .padding(.bottom, 24)

                            // Keypad
                            NumericKeypadView(
                                value: $viewModel.capitalInput,
                                displayValue: $viewModel.capitalRaw
                            )
                            .padding(.bottom, 24)

                            // Divider
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.1), .clear],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(height: 1)
                                .padding(.bottom, 24)

                            // Max Drawdown Slider
                            VStack(spacing: 16) {
                                HStack {
                                    Text("MAX DRAWDOWN LIMIT")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .tracking(1.5)
                                    Spacer()
                                    Text("\(viewModel.maxLossPercent.safeInt(fallback: 15))%")
                                        .font(.system(size: 26, weight: .light, design: .rounded))
                                        .foregroundStyle(viewModel.lossColor)
                                }

                                Slider(value: $viewModel.maxLossPercent, in: 1...50, step: 1)
                                    .tint(viewModel.lossColor)
                            }
                        }
                        .padding(24)
                        .glassCard(cornerRadius: 32)
                        .padding(.horizontal, 20)

                        Spacer(minLength: 32)
                    }
                }

                // MARK: CTA
                GradientCTAButton(label: "Run Simulation") {
                    appState.riskProfile = RiskProfileInput(
                        startingCapital: viewModel.capitalRaw,
                        timeHorizon: viewModel.selectedHorizon,
                        maxLossPercent: viewModel.maxLossPercent
                    )
                    appState.navigateToDashboard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .padding(.top, 12)
            }
        }
    }
}

// MARK: - Animated Glass Mascot

private struct MascotView: View {
    @State private var rotating = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.4), Color.teal.opacity(0.2), .clear],
                        center: .center, startRadius: 0, endRadius: 60
                    )
                )
                .blur(radius: 20)
                .frame(width: 120, height: 120)

            RoundedRectangle(cornerRadius: 28)
                .fill(.white.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.3), lineWidth: 1))
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(rotating ? 45 : 12))
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: rotating)

            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color.teal.opacity(0.9), Color.purple.opacity(0.9)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(rotating ? -45 : -12))
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: rotating)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.85))
                        .rotationEffect(.degrees(rotating ? -45 : -12))
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: rotating)
                )
        }
        .frame(width: 120, height: 120)
        .onAppear { rotating = true }
    }
}

// MARK: - Gradient CTA Button

struct GradientCTAButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                LinearGradient(
                    colors: [Color.teal.opacity(0.85), Color.purple.opacity(0.85)],
                    startPoint: .leading, endPoint: .trailing
                )

                Color.black.opacity(0.25)
                    .clipShape(RoundedRectangle(cornerRadius: 27))
                    .padding(1)

                HStack(spacing: 10) {
                    Text(label)
                        .font(.system(size: 17, weight: .medium))
                        .tracking(0.3)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.teal.opacity(0.9))
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 28))
        }
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
        VStack(spacing: 10) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handleKey(key)
                        } label: {
                            Text(key)
                                .font(.system(size: 18, weight: .light, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22)
                                        .stroke(.white.opacity(0.05), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 22))
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
            if let current = Double(value), current > 0 {
                value = String((current * 1000).safeInt())
            }
        default:
            if value.count < 8 { value += key }
        }
        displayValue = Double(value) ?? 0
    }
}

// MARK: - Shared: AuraBackground

struct AuraBackground: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.027, blue: 0.063)
                .ignoresSafeArea()

            Ellipse()
                .fill(Color.purple.opacity(0.22))
                .blur(radius: 80)
                .frame(width: 380, height: 380)
                .offset(x: -80, y: -300)
                .scaleEffect(pulse ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: pulse)

            Ellipse()
                .fill(Color.teal.opacity(0.18))
                .blur(radius: 70)
                .frame(width: 320, height: 320)
                .offset(x: 120, y: 80)
                .scaleEffect(pulse ? 0.95 : 1.05)
                .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: pulse)

            Ellipse()
                .fill(Color.indigo.opacity(0.18))
                .blur(radius: 70)
                .frame(width: 280, height: 280)
                .offset(x: 0, y: 400)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Shared: GlassCard modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 28) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
