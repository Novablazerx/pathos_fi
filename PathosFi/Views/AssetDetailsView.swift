import SwiftUI
import Charts

// MARK: - Asset Details View

struct AssetDetailsView: View {
    let asset: AssetInfo
    let options: [OptionsContract]

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var historicalPoints: [PriceDataPoint] = []
    @State private var projectedPoints:  [PriceDataPoint] = []
    @State private var shareQty: Int = 1

    private let fmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f
    }()

    private var holding: HeldAsset? {
        appState.holdings.first { $0.asset.ticker == asset.ticker }
    }

    private var displayPrice: Double {
        holding?.currentPrice ?? OptimisationEngine.referencePrices[asset.ticker] ?? 100
    }

    var body: some View {
        ZStack {
            AuraBackground()

            VStack(spacing: 0) {
                AssetDetailHeader(
                    asset: asset,
                    holding: holding,
                    displayPrice: displayPrice,
                    fmt: fmt,
                    onClose: { dismiss() }
                )

                ScrollView {
                    VStack(spacing: 16) {
                        AssetPriceChart(
                            historical: historicalPoints,
                            projected:  projectedPoints,
                            currentPrice: displayPrice
                        )

                        YourPositionPanel(
                            asset: asset,
                            holding: holding,
                            displayPrice: displayPrice,
                            shareQty: $shareQty,
                            fmt: fmt,
                            onAdd: addShares,
                            onDrop: dropShares
                        )

                        if !options.isEmpty {
                            ActiveOptionsSection(options: options, fmt: fmt)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear { generateChartData() }
    }

    private func generateChartData() {
        var rng = SeededRNG(seed: asset.ticker.hashValue)
        let monthlyVol = asset.annualVolatility / sqrt(12.0)
        let monthlyRet = asset.annualReturn / 12.0

        var price = displayPrice
        var rawHistory: [Double] = [price]
        for _ in 0..<12 {
            let noise = Double.random(in: -monthlyVol...monthlyVol, using: &rng)
            price /= max(1 + noise, 0.5)
            rawHistory.insert(price, at: 0)
        }
        historicalPoints = rawHistory.enumerated().map { i, p in
            PriceDataPoint(monthOffset: i - 12, price: p)
        }

        price = displayPrice
        projectedPoints = [PriceDataPoint(monthOffset: 0, price: price)]
        for i in 1...12 {
            let noise = Double.random(in: -monthlyVol * 0.4...monthlyVol * 0.4, using: &rng)
            price *= (1 + monthlyRet + noise)
            projectedPoints.append(PriceDataPoint(monthOffset: i, price: price))
        }
    }

    private func addShares() {
        let price = displayPrice
        if let idx = appState.holdings.firstIndex(where: { $0.asset.ticker == asset.ticker }) {
            let old = appState.holdings[idx]
            let newShares = old.shares + Double(shareQty)
            let newAvgCost = (old.shares * old.avgCost + Double(shareQty) * price) / newShares
            appState.holdings[idx] = HeldAsset(
                asset: old.asset, shares: newShares,
                avgCost: newAvgCost, currentPrice: old.currentPrice
            )
        } else {
            appState.holdings.append(HeldAsset(
                asset: asset, shares: Double(shareQty),
                avgCost: price, currentPrice: price
            ))
        }
    }

    private func dropShares() {
        guard let idx = appState.holdings.firstIndex(where: { $0.asset.ticker == asset.ticker }) else { return }
        let old = appState.holdings[idx]
        let remaining = old.shares - Double(shareQty)
        if remaining <= 0 {
            appState.holdings.remove(at: idx)
            dismiss()
        } else {
            appState.holdings[idx] = HeldAsset(
                asset: old.asset, shares: remaining,
                avgCost: old.avgCost, currentPrice: old.currentPrice
            )
        }
    }
}

// MARK: - Price Data Point

struct PriceDataPoint: Identifiable {
    let id = UUID()
    let monthOffset: Int
    let price: Double
}

// MARK: - Seeded RNG (deterministic chart shapes per ticker)

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) ^ 6364136223846793005
    }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Header

private struct AssetDetailHeader: View {
    let asset: AssetInfo
    let holding: HeldAsset?
    let displayPrice: Double
    let fmt: NumberFormatter
    let onClose: () -> Void

    private var accentColor: Color {
        switch asset.category {
        case .equity:        return Color.teal
        case .bond:          return Color.purple
        case .commodity:     return Color.orange
        case .inverseEquity: return Color.pink
        case .option:        return Color.indigo
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            Button(action: onClose) {
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
                Text(asset.category.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor.opacity(0.8))
                    .tracking(2)
                Text(asset.ticker)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 12)

            Spacer()

            if let h = holding {
                let gain = h.gainPct
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmt.string(from: NSNumber(value: h.value)) ?? "")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(gain >= 0 ? "+" : "")\(String(format: "%.1f", gain))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(gain >= 0 ? Color.teal : Color.pink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((gain >= 0 ? Color.teal : Color.pink).opacity(0.12))
                        .clipShape(Capsule())
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmt.string(from: NSNumber(value: displayPrice)) ?? "")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("NOT HELD")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Price Chart

private struct AssetPriceChart: View {
    let historical: [PriceDataPoint]
    let projected:  [PriceDataPoint]
    let currentPrice: Double

    @State private var selectedMonthOffset: Double? = nil

    private var allPrices: [Double] {
        (historical.map(\.price) + projected.map(\.price))
    }

    private func interpolatedPrice(at offset: Double) -> Double? {
        let all = (historical + projected).sorted { $0.monthOffset < $1.monthOffset }
        guard all.count >= 2 else { return nil }
        guard let lo = all.last(where: { Double($0.monthOffset) <= offset }),
              let hi = all.first(where: { Double($0.monthOffset) >= offset }) else {
            return all.first?.price
        }
        guard lo.monthOffset != hi.monthOffset else { return lo.price }
        let t = (offset - Double(lo.monthOffset)) / Double(hi.monthOffset - lo.monthOffset)
        return lo.price + t * (hi.price - lo.price)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PERFORMANCE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1.5)
                Spacer()
                HStack(spacing: 12) {
                    LegendDot(color: Color.teal, label: "Historical", dashed: false)
                    LegendDot(color: Color.teal.opacity(0.5), label: "Projected", dashed: true)
                }
            }

            Chart {
                ForEach(historical) { pt in
                    LineMark(
                        x: .value("Month", pt.monthOffset),
                        y: .value("Price", pt.price)
                    )
                    .foregroundStyle(by: .value("Segment", "Historical"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                ForEach(projected) { pt in
                    LineMark(
                        x: .value("Month", pt.monthOffset),
                        y: .value("Price", pt.price)
                    )
                    .foregroundStyle(by: .value("Segment", "Projected"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }

                RuleMark(x: .value("Today", 0))
                    .foregroundStyle(.white.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("TODAY")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                            .tracking(1.5)
                    }

                PointMark(
                    x: .value("Month", 0),
                    y: .value("Price", currentPrice)
                )
                .foregroundStyle(.white)
                .symbolSize(70)
            }
            .chartForegroundStyleScale([
                "Historical": Color.teal,
                "Projected":  Color.teal.opacity(0.5),
            ])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: [-12, -6, 0, 6, 12]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v == 0 ? "Now" : (v < 0 ? "\(-v)m ago" : "+\(v)m"))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("$\(Int(v))")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedMonthOffset)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plot = geo[proxy.plotAreaFrame]
                    if let offset = selectedMonthOffset,
                       let xPos  = proxy.position(forX: offset),
                       let price = interpolatedPrice(at: offset) {
                        let xScreen = plot.minX + xPos
                        Rectangle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 1, height: plot.height)
                            .position(x: xScreen, y: plot.midY)
                        Text("$\(Int(price.rounded()))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.teal.opacity(0.85))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 4)
                            .position(
                                x: min(max(xScreen, 30), plot.maxX - 30),
                                y: plot.minY + 18
                            )
                    }
                }
            }
            .frame(height: 220)
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
        .padding(.horizontal, 16)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    let dashed: Bool

    var body: some View {
        HStack(spacing: 4) {
            if dashed {
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color)
                            .frame(width: 4, height: 2)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 14, height: 2)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

// MARK: - Your Position Panel

private struct YourPositionPanel: View {
    let asset: AssetInfo
    let holding: HeldAsset?
    let displayPrice: Double
    @Binding var shareQty: Int
    let fmt: NumberFormatter
    let onAdd: () -> Void
    let onDrop: () -> Void

    private var accentColor: Color {
        switch asset.category {
        case .equity:        return Color.teal
        case .bond:          return Color.purple
        case .commodity:     return Color.orange
        case .inverseEquity: return Color.pink
        case .option:        return Color.indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR POSITION")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(1.5)

            // Current position row
            if let h = holding {
                HStack(spacing: 12) {
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .overlay(Circle().stroke(accentColor.opacity(0.5), lineWidth: 1))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(asset.ticker.prefix(3))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(accentColor)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(format: h.shares == h.shares.rounded() ? "%.0f" : "%.2f", h.shares)) shares")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Avg \(fmt.string(from: NSNumber(value: h.avgCost)) ?? "") / share")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(fmt.string(from: NSNumber(value: h.value)) ?? "")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        let gain = h.gainPct
                        Text("\(gain >= 0 ? "+" : "")\(String(format: "%.1f", gain))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(gain >= 0 ? Color.teal : Color.pink)
                    }
                }
                .padding(14)
                .background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Not in portfolio")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text(fmt.string(from: NSNumber(value: displayPrice)) ?? "")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(14)
                .background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
            }

            // Quantity stepper
            HStack {
                Text("Quantity")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                HStack(spacing: 0) {
                    Button {
                        if shareQty > 1 { shareQty -= 1 }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(shareQty > 1 ? Color.teal : .white.opacity(0.2))
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(shareQty <= 1)

                    Text("\(shareQty)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 52)

                    Button {
                        shareQty += 1
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.teal)
                            .frame(width: 38, height: 38)
                            .background(Color.teal.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            // Action buttons
            if holding != nil {
                HStack(spacing: 10) {
                    Button(action: onAdd) {
                        Label("Add \(shareQty)", systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.teal)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button(action: onDrop) {
                        Label("Drop \(shareQty)", systemImage: "minus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.pink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.pink.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.pink.opacity(0.3), lineWidth: 1))
                    }
                }
            } else {
                Button(action: onAdd) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add to Portfolio")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
        .padding(.horizontal, 16)
    }
}

// MARK: - Active Options Section

private struct ActiveOptionsSection: View {
    let options: [OptionsContract]
    let fmt: NumberFormatter

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ACTIVE OPTIONS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(1.5)

            VStack(spacing: 10) {
                ForEach(options) { contract in
                    OptionsContractRow(contract: contract, fmt: fmt)
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 28)
        .padding(.horizontal, 16)
    }
}

private struct OptionsContractRow: View {
    let contract: OptionsContract
    let fmt: NumberFormatter

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, ''yy"
        return f
    }()

    private var typeColor: Color { contract.type == .call ? Color.teal : Color.pink }

    var body: some View {
        HStack(spacing: 12) {
            Text(contract.type.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(typeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(typeColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(typeColor.opacity(0.3), lineWidth: 1))
                .frame(width: 46)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("$\(Int(contract.strikePrice)) strike")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("×\(contract.contracts)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text("Exp \(Self.dateFormatter.string(from: contract.expiryDate))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(fmt.string(from: NSNumber(value: contract.totalValue)) ?? "")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                let pnl = contract.pnlPct
                Text("\(pnl >= 0 ? "+" : "")\(String(format: "%.1f", pnl))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(pnl >= 0 ? Color.teal : Color.pink)
            }
        }
        .padding(14)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}
