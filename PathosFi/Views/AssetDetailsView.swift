import SwiftUI
import Charts

// MARK: - Asset Details View

struct AssetDetailsView: View {
    let holding: HeldAsset
    let options: [OptionsContract]

    @Environment(\.dismiss) private var dismiss

    @State private var historicalPoints: [PriceDataPoint] = []
    @State private var projectedPoints:  [PriceDataPoint] = []

    private let fmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        ZStack {
            AuraBackground()

            VStack(spacing: 0) {
                AssetDetailHeader(holding: holding, fmt: fmt, onClose: { dismiss() })

                ScrollView {
                    VStack(spacing: 16) {
                        AssetPriceChart(
                            historical: historicalPoints,
                            projected:  projectedPoints,
                            currentPrice: holding.currentPrice
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
        var rng = SeededRNG(seed: holding.asset.ticker.hashValue)
        let monthlyVol = holding.asset.annualVolatility / sqrt(12.0)
        let monthlyRet = holding.asset.annualReturn / 12.0

        // Historical: work backwards from currentPrice over 12 months
        var price = holding.currentPrice
        var rawHistory: [Double] = [price]
        for _ in 0..<12 {
            let noise = Double.random(in: -monthlyVol...monthlyVol, using: &rng)
            price /= max(1 + noise, 0.5)
            rawHistory.insert(price, at: 0)
        }
        historicalPoints = rawHistory.enumerated().map { i, p in
            PriceDataPoint(monthOffset: i - 12, price: p)
        }

        // Projected: grow forward from currentPrice over 12 months
        price = holding.currentPrice
        projectedPoints = [PriceDataPoint(monthOffset: 0, price: price)]
        for i in 1...12 {
            let noise = Double.random(in: -monthlyVol * 0.4...monthlyVol * 0.4, using: &rng)
            price *= (1 + monthlyRet + noise)
            projectedPoints.append(PriceDataPoint(monthOffset: i, price: price))
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
    let holding: HeldAsset
    let fmt: NumberFormatter
    let onClose: () -> Void

    private var accentColor: Color {
        switch holding.asset.category {
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
                Text(holding.asset.category.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor.opacity(0.8))
                    .tracking(2)
                Text(holding.asset.ticker)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 12)

            Spacer()

            let gain = holding.gainPct
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmt.string(from: NSNumber(value: holding.value)) ?? "")
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
                // Historical — solid teal line
                ForEach(historical) { pt in
                    LineMark(
                        x: .value("Month", pt.monthOffset),
                        y: .value("Price", pt.price)
                    )
                    .foregroundStyle(by: .value("Segment", "Historical"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // Projected — dashed, lighter
                ForEach(projected) { pt in
                    LineMark(
                        x: .value("Month", pt.monthOffset),
                        y: .value("Price", pt.price)
                    )
                    .foregroundStyle(by: .value("Segment", "Projected"))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }

                // Current day vertical rule
                RuleMark(x: .value("Today", 0))
                    .foregroundStyle(.white.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("TODAY")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                            .tracking(1.5)
                    }

                // Current day price node
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
            // Type badge
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
