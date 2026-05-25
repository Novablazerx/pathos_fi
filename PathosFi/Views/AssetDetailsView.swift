import SwiftUI
import Charts

// MARK: - Asset Details View

struct AssetDetailsView: View {
    let asset: AssetInfo

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var historicalPoints: [PriceDataPoint] = []
    @State private var projectedPoints:  [PriceDataPoint] = []
    @State private var shareQty: Int = 1
    @State private var tradingOption: AvailableOption? = nil
    @State private var chainOptions: [BackendAPIClient.OptionOut] = []
    @State private var chainLoaded = false
    @State private var sellingOption: OptionsContract? = nil

    private let fmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f
    }()

    private var holding: HeldAsset? {
        appState.holdings.first { $0.asset.ticker == asset.ticker }
    }

    private var liveOptions: [OptionsContract] {
        appState.optionsByTicker[asset.ticker] ?? []
    }

    private var displayPrice: Double {
        holding?.currentPrice ?? OptimisationEngine.referencePrices[asset.ticker] ?? 100
    }

    private static let expiryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(abbreviation: "UTC")
        return f
    }()

    private var heldOptionIds: Set<Int> {
        Set(appState.optionsByTicker[asset.ticker]?.compactMap { $0.optionId } ?? [])
    }

    private var availableChain: [AvailableOption] {
        chainOptions.compactMap { opt in
            guard !heldOptionIds.contains(opt.optionId) else { return nil }
            guard let typeStr = opt.optionType,
                  let strike  = opt.strikePrice,
                  let premium = opt.premium,
                  let expiryStr = opt.expiryDate,
                  let expiry = Self.expiryDateFormatter.date(from: expiryStr) else { return nil }
            let optType: OptionType = typeStr.lowercased() == "call" ? .call : .put
            let days = max(Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 1, 1)
            return AvailableOption(optionId: opt.optionId, type: optType,
                                   strikePrice: strike, expiryDate: expiry,
                                   premium: premium, daysToExpiry: days)
        }
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
                            currentPrice: projectedPoints.first?.price ?? displayPrice
                        )

                        YourPositionPanel(
                            asset: asset,
                            holding: holding,
                            displayPrice: displayPrice,
                            shareQty: $shareQty,
                            fmt: fmt,
                            onAdd: { addShares() },
                            onDrop: dropShares
                        )

                        ActiveOptionsSection(
                            options: liveOptions,
                            fmt: fmt,
                            onSell: { contract in sellingOption = contract }
                        )

                        AvailableOptionsChain(
                            chain: availableChain,
                            isLoaded: chainLoaded,
                            asset: asset,
                            fmt: fmt,
                            onTrade: { opt in tradingOption = opt }
                        )

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .task { await loadChartData() }
        .task { await loadOptionsChain() }
        .sheet(item: $sellingOption) { contract in
            OptionSellModal(
                contract: contract,
                asset: asset,
                displayPrice: displayPrice,
                fmt: fmt,
                onExecute: { contractsToSell in
                    sellOption(contract, contractsToSell: contractsToSell)
                    sellingOption = nil
                }
            )
        }
        .sheet(item: $tradingOption) { opt in
            OptionTradeModal(
                option: opt,
                asset: asset,
                displayPrice: displayPrice,
                fmt: fmt,
                onExecute: { contracts, bundle in
                    buyOption(opt, contracts: contracts, bundleShares: bundle)
                    tradingOption = nil
                }
            )
            .environmentObject(appState)
        }
    }

    // MARK: - Chart generation

    private func generateChartData() {
        var rng = SeededRNG(seed: asset.ticker.hashValue)
        let dailyVol = asset.annualVolatility / sqrt(252.0)
        let dailyRet = asset.annualReturn / 252.0
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var price = displayPrice
        var rawHistory: [Double] = []
        for _ in 0 ..< 30 {
            let noise = Double.random(in: -dailyVol ... dailyVol, using: &rng)
            price /= max(1 + noise, 0.5)
            rawHistory.insert(price, at: 0)
        }
        historicalPoints = rawHistory.enumerated().compactMap { i, p in
            cal.date(byAdding: .day, value: i - 30, to: today).map { PriceDataPoint(date: $0, price: p) }
        }

        price = displayPrice
        projectedPoints = []
        for i in 0 ... 30 {
            guard let date = cal.date(byAdding: .day, value: i, to: today) else { continue }
            if i > 0 {
                let noise = Double.random(in: -dailyVol * 0.4 ... dailyVol * 0.4, using: &rng)
                price *= (1 + dailyRet + noise)
            }
            projectedPoints.append(PriceDataPoint(date: date, price: price))
        }
    }

    private func loadChartData() async {
        /*generateChartData()*/  // display seeded fallback immediately

        guard let assetId = appState.assetIdByTicker[asset.ticker] else {
            print("[Chart] \(asset.ticker): no assetId in assetIdByTicker — keys: \(appState.assetIdByTicker.keys.sorted())")
            return
        }

        let marketData: BackendAPIClient.MarketDataResponse
        do {
            marketData = try await appState.apiClient.fetchMarketData(assetId: assetId)
        } catch {
            print("[Chart] \(asset.ticker) fetchMarketData failed: \(error)")
            return
        }

        print("[Chart] \(asset.ticker) — history: \(marketData.priceHistory.count) rows, forecast: \(marketData.priceForecast30d.count) points")

        guard !marketData.priceHistory.isEmpty || !marketData.priceForecast30d.isEmpty else {
            print("[Chart] \(asset.ticker): both arrays empty, keeping seeded data")
            return
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = TimeZone(abbreviation: "UTC")

        var histLookup: [String: Double] = [:]
        for row in marketData.priceHistory { histLookup[row.date] = row.close }

        var forecastLookup: [String: Double] = [:]
        for pt in marketData.priceForecast30d { forecastLookup[pt.date] = pt.price }

        print("[Chart] \(asset.ticker) histLookup keys: \(histLookup.keys.sorted())")
        print("[Chart] \(asset.ticker) forecastLookup keys: \(forecastLookup.keys.sorted())")

        var lastPrice: Double = marketData.priceHistory.first.map { $0.close } ?? displayPrice
        var histPoints: [PriceDataPoint] = []
        for dayOffset in -30 ..< 0 {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if let p = histLookup[dateFmt.string(from: date)] { lastPrice = p }
            histPoints.append(PriceDataPoint(date: date, price: lastPrice))
        }

        var lastForecastPrice: Double = histPoints.last?.price ?? displayPrice
        var forecastPoints: [PriceDataPoint] = []
        for dayOffset in 0 ... 30 {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if let p = forecastLookup[dateFmt.string(from: date)] { lastForecastPrice = p }
            forecastPoints.append(PriceDataPoint(date: date, price: lastForecastPrice))
        }

        historicalPoints = histPoints
        projectedPoints = forecastPoints
    }

    // MARK: - Options chain fetch

    private func loadOptionsChain() async {
        guard let assetId = appState.assetIdByTicker[asset.ticker] else {
            chainLoaded = true
            return
        }
        chainOptions = (try? await appState.apiClient.fetchAllAssetOptions(assetId: assetId)) ?? []
        chainLoaded = true
    }

    // MARK: - Trade actions

    private func addShares(qty: Double? = nil) {
        let q = qty ?? Double(shareQty)
        let price = displayPrice
        let newShares: Double
        let newAvgCost: Double
        if let idx = appState.holdings.firstIndex(where: { $0.asset.ticker == asset.ticker }) {
            let old = appState.holdings[idx]
            newShares = old.shares + q
            newAvgCost = (old.shares * old.avgCost + q * price) / newShares
            appState.holdings[idx] = HeldAsset(asset: old.asset, shares: newShares,
                                               avgCost: newAvgCost, currentPrice: old.currentPrice)
        } else {
            newShares = q
            newAvgCost = price
            appState.holdings.append(HeldAsset(asset: asset, shares: newShares,
                                               avgCost: newAvgCost, currentPrice: price))
        }
        guard let assetId = appState.assetIdByTicker[asset.ticker],
              let userId  = appState.currentUser?.userId else { return }
        appState.adjustCashBalance(by: -(q * price))
        Task {
            try? await appState.apiClient.upsertUserAsset(userId: userId, assetId: assetId,
                                                          quantity: newShares, avgCostBasis: newAvgCost)
        }
    }

    private func dropShares() {
        guard let idx = appState.holdings.firstIndex(where: { $0.asset.ticker == asset.ticker }) else { return }
        let old = appState.holdings[idx]
        let remaining = old.shares - Double(shareQty)
        guard let assetId = appState.assetIdByTicker[asset.ticker],
              let userId  = appState.currentUser?.userId else { return }
        let sharesSold = min(Double(shareQty), old.shares)
        let proceeds   = sharesSold * displayPrice
        if remaining <= 0 {
            appState.holdings.remove(at: idx)
            appState.adjustCashBalance(by: proceeds)
            Task { try? await appState.apiClient.deleteUserAsset(userId: userId, assetId: assetId) }
            dismiss()
        } else {
            appState.holdings[idx] = HeldAsset(asset: old.asset, shares: remaining,
                                               avgCost: old.avgCost, currentPrice: old.currentPrice)
            appState.adjustCashBalance(by: proceeds)
            Task {
                try? await appState.apiClient.upsertUserAsset(userId: userId, assetId: assetId,
                                                              quantity: remaining, avgCostBasis: old.avgCost)
            }
        }
    }

    private func buyOption(_ option: AvailableOption, contracts: Int, bundleShares: Bool) {
        var arr = appState.optionsByTicker[asset.ticker] ?? []
        let existing = arr.first(where: { $0.optionId == option.optionId })?.contracts ?? 0
        let totalContracts = existing + contracts
        let updated = OptionsContract(optionId: option.optionId,
                                      underlyingTicker: asset.ticker,
                                      type: option.type,
                                      strikePrice: option.strikePrice,
                                      expiryDate: option.expiryDate,
                                      contracts: totalContracts,
                                      costBasis: option.premium,
                                      currentValue: option.premium)
        if let idx = arr.firstIndex(where: { $0.optionId == option.optionId }) {
            arr[idx] = updated
        } else {
            arr.append(updated)
        }
        appState.optionsByTicker[asset.ticker] = arr

        guard let userId = appState.currentUser?.userId else { return }
        let optionCost = option.premium * Double(contracts) * 100
        appState.adjustCashBalance(by: -optionCost)
        Task {
            try? await appState.apiClient.upsertUserOption(userId: userId,
                                                           optionId: option.optionId,
                                                           contractsHeld: totalContracts)
        }
        if bundleShares { addShares(qty: Double(contracts * 100)) }
    }

    private func sellOption(_ contract: OptionsContract, contractsToSell: Int) {
        var arr = appState.optionsByTicker[asset.ticker] ?? []
        guard let idx = arr.firstIndex(where: { $0.id == contract.id }) else { return }
        let remaining = arr[idx].contracts - contractsToSell
        guard let userId = appState.currentUser?.userId,
              let optionId = contract.optionId else { return }
        let proceeds = contract.currentValue * Double(contractsToSell) * 100
        if remaining <= 0 {
            arr.remove(at: idx)
            appState.optionsByTicker[asset.ticker] = arr.isEmpty ? nil : arr
            appState.adjustCashBalance(by: proceeds)
            Task { try? await appState.apiClient.deleteUserOption(userId: userId, optionId: optionId) }
        } else {
            let updated = OptionsContract(optionId: optionId,
                                          underlyingTicker: contract.underlyingTicker,
                                          type: contract.type,
                                          strikePrice: contract.strikePrice,
                                          expiryDate: contract.expiryDate,
                                          contracts: remaining,
                                          costBasis: contract.costBasis,
                                          currentValue: contract.currentValue)
            arr[idx] = updated
            appState.optionsByTicker[asset.ticker] = arr
            appState.adjustCashBalance(by: proceeds)
            Task { try? await appState.apiClient.upsertUserOption(userId: userId, optionId: optionId,
                                                                   contractsHeld: remaining) }
        }
    }
}

// MARK: - Price Data Point

struct PriceDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let price: Double
}

// MARK: - Seeded RNG

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

    @State private var selectedDate: Date? = nil

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var axisMarkDates: [Date] {
        let cal = Calendar.current
        return [-30, -15, 0, 15, 30].compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private func interpolatedPrice(at date: Date) -> Double? {
        let all = (historical + projected).sorted { $0.date < $1.date }
        guard all.count >= 2 else { return nil }
        let t = date.timeIntervalSinceReferenceDate
        guard let lo = all.last(where: { $0.date.timeIntervalSinceReferenceDate <= t }),
              let hi = all.first(where: { $0.date.timeIntervalSinceReferenceDate >= t }) else {
            return all.first?.price
        }
        guard lo.date != hi.date else { return lo.price }
        let loT = lo.date.timeIntervalSinceReferenceDate
        let hiT = hi.date.timeIntervalSinceReferenceDate
        let fraction = (t - loT) / (hiT - loT)
        return lo.price + fraction * (hi.price - lo.price)
    }

    var body: some View {
        let cal = Calendar.current
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
                    LineMark(x: .value("Date", pt.date), y: .value("Price", pt.price))
                        .foregroundStyle(by: .value("Segment", "Historical"))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(projected) { pt in
                    LineMark(x: .value("Date", pt.date), y: .value("Price", pt.price))
                        .foregroundStyle(by: .value("Segment", "Projected"))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                RuleMark(x: .value("Today", today))
                    .foregroundStyle(.white.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("TODAY")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                            .tracking(1.5)
                    }
                PointMark(x: .value("Date", today), y: .value("Price", currentPrice))
                    .foregroundStyle(.white)
                    .symbolSize(70)
            }
            .chartForegroundStyleScale(["Historical": Color.teal, "Projected": Color.teal.opacity(0.5)])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: axisMarkDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            let days = cal.dateComponents([.day], from: today, to: d).day ?? 0
                            Text(days == 0 ? "Now" : (days < 0 ? "\(-days)d ago" : "+\(days)d"))
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("$\(Int(v))").font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plot = geo[proxy.plotAreaFrame]
                    if let date = selectedDate,
                       let xPos  = proxy.position(forX: date),
                       let price = interpolatedPrice(at: date) {
                        let xScreen = plot.minX + xPos
                        Rectangle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 1, height: plot.height)
                            .position(x: xScreen, y: plot.midY)
                        Text("$\(Int(price.rounded()))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.teal.opacity(0.85))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 4)
                            .position(x: min(max(xScreen, 30), plot.maxX - 30), y: plot.minY + 18)
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
    let color: Color; let label: String; let dashed: Bool
    var body: some View {
        HStack(spacing: 4) {
            if dashed {
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 4, height: 2)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 14, height: 2)
            }
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
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
        case .equity: return .teal; case .bond: return .purple
        case .commodity: return .orange; case .inverseEquity: return .pink; case .option: return .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR POSITION")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5)).tracking(1.5)

            if let h = holding {
                HStack(spacing: 12) {
                    Circle().fill(accentColor.opacity(0.2))
                        .overlay(Circle().stroke(accentColor.opacity(0.5), lineWidth: 1))
                        .frame(width: 36, height: 36)
                        .overlay(Text(asset.ticker.prefix(3)).font(.system(size: 9, weight: .bold)).foregroundStyle(accentColor))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(format: h.shares == h.shares.rounded() ? "%.0f" : "%.2f", h.shares)) shares")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Text("Avg \(fmt.string(from: NSNumber(value: h.avgCost)) ?? "") / share")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(fmt.string(from: NSNumber(value: h.value)) ?? "")
                            .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        let gain = h.gainPct
                        Text("\(gain >= 0 ? "+" : "")\(String(format: "%.1f", gain))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(gain >= 0 ? Color.teal : Color.pink)
                    }
                }
                .padding(14).background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.dashed").font(.system(size: 16)).foregroundStyle(.white.opacity(0.3))
                    Text("Not in portfolio").font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Text(fmt.string(from: NSNumber(value: displayPrice)) ?? "")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
                .padding(14).background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
            }

            HStack {
                Text("Quantity").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                HStack(spacing: 0) {
                    Button { if shareQty > 1 { shareQty -= 1 } } label: {
                        Image(systemName: "minus").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(shareQty > 1 ? Color.teal : .white.opacity(0.2))
                            .frame(width: 38, height: 38).background(.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.disabled(shareQty <= 1)
                    Text("\(shareQty)").font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white).frame(width: 52)
                    Button { shareQty += 1 } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.teal).frame(width: 38, height: 38)
                            .background(Color.teal.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if holding != nil {
                HStack(spacing: 10) {
                    Button(action: onAdd) {
                        Label("Add \(shareQty)", systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.teal).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button(action: onDrop) {
                        Label("Drop \(shareQty)", systemImage: "minus")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.pink)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.pink.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 14))
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
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color.teal).clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .padding(20).glassCard(cornerRadius: 28).padding(.horizontal, 16)
    }
}

// MARK: - Active Options Section (live holdings)

private struct ActiveOptionsSection: View {
    let options: [OptionsContract]
    let fmt: NumberFormatter
    var onSell: ((OptionsContract) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ACTIVE OPTIONS HOLDINGS")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5)).tracking(1.5)

            if options.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "doc.plaintext").font(.system(size: 15)).foregroundStyle(.white.opacity(0.2))
                    Text("No options held for this asset")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06), lineWidth: 1))
            } else {
                VStack(spacing: 10) {
                    ForEach(options) { contract in
                        OptionsContractRow(contract: contract, fmt: fmt,
                                           onSell: { onSell?(contract) })
                    }
                }
            }
        }
        .padding(20).glassCard(cornerRadius: 28).padding(.horizontal, 16)
    }
}

private struct OptionsContractRow: View {
    let contract: OptionsContract
    let fmt: NumberFormatter
    var onSell: (() -> Void)? = nil

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, ''yy"; return f
    }()

    private var typeColor: Color { contract.type == .call ? Color.teal : Color.pink }

    var body: some View {
        HStack(spacing: 12) {
            Text(contract.type.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold)).foregroundStyle(typeColor)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(typeColor.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(typeColor.opacity(0.3), lineWidth: 1))
                .frame(width: 46)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("$\(Int(contract.strikePrice)) strike").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("×\(contract.contracts)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                }
                Text("Exp \(Self.dateFmt.string(from: contract.expiryDate))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmt.string(from: NSNumber(value: contract.totalValue)) ?? "")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                let pnl = contract.pnlPct
                Text("\(pnl >= 0 ? "+" : "")\(String(format: "%.1f", pnl))%")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(pnl >= 0 ? Color.teal : Color.pink)
            }
            Button(action: { onSell?() }) {
                Text("Sell")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.pink)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.pink.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.pink.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(14).background(.white.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Available Options Chain

private struct AvailableOptionsChain: View {
    let chain: [AvailableOption]
    let isLoaded: Bool
    let asset: AssetInfo
    let fmt: NumberFormatter
    let onTrade: (AvailableOption) -> Void

    @State private var selectedDays: Int = 0
    @State private var selectedType: OptionType = .call

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private var availableDays: [Int] {
        Array(Set(chain.map { $0.daysToExpiry })).sorted()
    }

    private var filtered: [AvailableOption] {
        chain.filter { $0.daysToExpiry == selectedDays && $0.type == selectedType }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AVAILABLE OPTIONS CHAIN")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5)).tracking(1.5)

            if !isLoaded {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8).tint(Color.teal)
                    Text("Loading options chain…")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if chain.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "doc.plaintext").font(.system(size: 15)).foregroundStyle(.white.opacity(0.2))
                    Text("No options available for this asset")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                // Maturity filter + Call/Put toggle
                HStack(alignment: .center, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableDays, id: \.self) { days in
                                Button { selectedDays = days } label: {
                                    Text("\(days)d")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(selectedDays == days ? Color(red: 0.039, green: 0.027, blue: 0.063) : .white.opacity(0.5))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(selectedDays == days ? Color.teal : Color.white.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    HStack(spacing: 0) {
                        ForEach([OptionType.call, .put], id: \.rawValue) { type in
                            Button { selectedType = type } label: {
                                Text(type.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(selectedType == type ? Color(red: 0.039, green: 0.027, blue: 0.063) : .white.opacity(0.5))
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(selectedType == type
                                        ? (type == .call ? Color.teal : Color.pink)
                                        : Color.white.opacity(0.06))
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
                    .fixedSize()
                }

                // Column headers
                HStack {
                    Text("STRIKE").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.3)).tracking(1).frame(width: 64, alignment: .leading)
                    Text("PREMIUM").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.3)).tracking(1)
                    Spacer()
                    Text("EXPIRY").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.3)).tracking(1)
                }
                .padding(.horizontal, 4)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filtered) { opt in
                            AvailableOptionRow(option: opt, fmt: fmt, dateFmt: Self.dateFmt, onTrade: { onTrade(opt) })
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(20).glassCard(cornerRadius: 28).padding(.horizontal, 16)
        .task(id: chain.count) {
            if let first = availableDays.first, !availableDays.contains(selectedDays) {
                selectedDays = first
            }
        }
    }
}

private struct AvailableOptionRow: View {
    let option: AvailableOption
    let fmt: NumberFormatter
    let dateFmt: DateFormatter
    let onTrade: () -> Void

    private var typeColor: Color { option.type == .call ? Color.teal : Color.pink }
    private var premiumStr: String { String(format: "$%.2f", option.premium) }

    var body: some View {
        HStack(spacing: 12) {
            Text("$\(Int(option.strikePrice))")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(premiumStr).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(typeColor)
                Text("per share").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
            }
            Spacer()
            Text(dateFmt.string(from: option.expiryDate))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            Button(action: onTrade) {
                Text("Trade")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(typeColor)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(typeColor.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(typeColor.opacity(0.3), lineWidth: 1))
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 6)
        .background(.white.opacity(0.02)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Option Trade Modal

struct OptionTradeModal: View {
    let option: AvailableOption
    let asset: AssetInfo
    let displayPrice: Double
    let fmt: NumberFormatter
    let onExecute: (Int, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contractQty: Int = 1
    @State private var bundleShares: Bool = false

    private var typeColor: Color { option.type == .call ? Color.teal : Color.pink }
    private var optionCost: Double   { option.premium * Double(contractQty) * 100 }
    private var bundleShareCount: Int { contractQty * 100 }
    private var bundleCost: Double   { displayPrice * Double(bundleShareCount) }
    private var grandTotal: Double   { optionCost + (bundleShares ? bundleCost : 0) }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.027, blue: 0.063).ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.15)).frame(width: 36, height: 4).padding(.top, 14).padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 20) {

                        // Option summary card
                        VStack(spacing: 12) {
                            HStack {
                                Text(option.type.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(typeColor).tracking(2)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(typeColor.opacity(0.12)).clipShape(Capsule())
                                    .overlay(Capsule().stroke(typeColor.opacity(0.3), lineWidth: 1))
                                Spacer()
                                Text(asset.ticker)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                            Divider().background(.white.opacity(0.08))
                            HStack {
                                statPill(label: "STRIKE", value: "$\(Int(option.strikePrice))")
                                Spacer()
                                statPill(label: "PREMIUM", value: String(format: "$%.2f", option.premium))
                                Spacer()
                                statPill(label: "EXPIRES", value: Self.dateFmt.string(from: option.expiryDate))
                            }
                        }
                        .padding(18).glassCard(cornerRadius: 22).padding(.horizontal, 20)

                        // Contracts stepper
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CONTRACTS")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5)).tracking(1.5)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(contractQty) contract\(contractQty == 1 ? "" : "s")")
                                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                    Text("= \(contractQty * 100) shares exposure")
                                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                HStack(spacing: 0) {
                                    Button { if contractQty > 1 { contractQty -= 1 } } label: {
                                        Image(systemName: "minus").font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(contractQty > 1 ? typeColor : .white.opacity(0.2))
                                            .frame(width: 40, height: 40).background(.white.opacity(0.05))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }.disabled(contractQty <= 1)
                                    Text("\(contractQty)")
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white).frame(width: 48)
                                    Button { contractQty += 1 } label: {
                                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(typeColor).frame(width: 40, height: 40)
                                            .background(typeColor.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                        .padding(18).glassCard(cornerRadius: 22).padding(.horizontal, 20)

                        // Bundle toggle
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: option.type == .call ? "arrow.up.right.circle.fill" : "shield.fill")
                                            .foregroundStyle(typeColor).font(.system(size: 14))
                                        Text(option.type == .call ? "Covered Call Strategy" : "Protective Put Strategy")
                                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                    }
                                    Text("Also buy \(bundleShareCount) \(asset.ticker) shares")
                                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                Toggle("", isOn: $bundleShares)
                                    .toggleStyle(SwitchToggleStyle(tint: typeColor))
                                    .labelsHidden()
                            }
                            if bundleShares {
                                HStack {
                                    Text("\(bundleShareCount) × \(fmt.string(from: NSNumber(value: displayPrice)) ?? "")")
                                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                    Text(fmt.string(from: NSNumber(value: bundleCost)) ?? "")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                                }
                                .padding(.top, 2)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: bundleShares)
                        .padding(18).glassCard(cornerRadius: 22).padding(.horizontal, 20)

                        // Cost summary + execute
                        VStack(spacing: 14) {
                            HStack {
                                Text("Option premium").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text(fmt.string(from: NSNumber(value: optionCost)) ?? "")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                            if bundleShares {
                                HStack {
                                    Text("Shares").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                    Text(fmt.string(from: NSNumber(value: bundleCost)) ?? "")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                }
                                .transition(.opacity)
                            }
                            Divider().background(.white.opacity(0.08))
                            HStack {
                                Text("Total").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                Spacer()
                                Text(fmt.string(from: NSNumber(value: grandTotal)) ?? "")
                                    .font(.system(size: 20, weight: .light, design: .rounded)).foregroundStyle(typeColor)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: bundleShares)
                        .padding(18).glassCard(cornerRadius: 22).padding(.horizontal, 20)

                        Button { onExecute(contractQty, bundleShares) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Execute Trade")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.039, green: 0.027, blue: 0.063))
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(typeColor).clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .padding(.horizontal, 20)

                        Spacer(minLength: 20)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35)).tracking(1)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        }
    }
}

// MARK: - Option Sell Modal

private struct OptionSellModal: View {
    let contract: OptionsContract
    let asset: AssetInfo
    let displayPrice: Double
    let fmt: NumberFormatter
    let onExecute: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contractQty: Int = 1

    private var typeColor: Color { contract.type == .call ? Color.teal : Color.pink }
    private var proceeds: Double { contract.currentValue * Double(contractQty) * 100 }
    private var maxSellable: Int { contract.contracts }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.027, blue: 0.063).ignoresSafeArea()

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.15)).frame(width: 36, height: 4)
                    .padding(.top, 14).padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 20) {

                        // Option summary card
                        VStack(spacing: 12) {
                            HStack {
                                HStack(spacing: 6) {
                                    Text(contract.type.rawValue.uppercased())
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(typeColor).tracking(2)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(typeColor.opacity(0.12)).clipShape(Capsule())
                                        .overlay(Capsule().stroke(typeColor.opacity(0.3), lineWidth: 1))
                                    Text("SELL")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Color.pink).tracking(2)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.pink.opacity(0.12)).clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.pink.opacity(0.3), lineWidth: 1))
                                }
                                Spacer()
                                Text(asset.ticker)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                            Divider().background(.white.opacity(0.08))
                            HStack {
                                VStack(spacing: 3) {
                                    Text("STRIKE").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35)).tracking(1)
                                    Text("$\(Int(contract.strikePrice))").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                }
                                Spacer()
                                VStack(spacing: 3) {
                                    Text("HELD").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35)).tracking(1)
                                    Text("\(contract.contracts) contract\(contract.contracts == 1 ? "" : "s")")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                }
                                Spacer()
                                VStack(spacing: 3) {
                                    Text("EXPIRES").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35)).tracking(1)
                                    Text(Self.dateFmt.string(from: contract.expiryDate))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                }
                            }
                        }
                        .padding(18).glassCard(cornerRadius: 22).padding(.horizontal, 20)

                        // Contracts stepper
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CONTRACTS TO SELL")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5)).tracking(1.5)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(contractQty) of \(maxSellable) contract\(maxSellable == 1 ? "" : "s")")
                                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                    Text("= \(contractQty * 100) shares exposure")
                                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                HStack(spacing: 0) {
                                    Button { if contractQty > 1 { contractQty -= 1 } } label: {
                                        Image(systemName: "minus").font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(contractQty > 1 ? Color.pink : .white.opacity(0.2))
                                            .frame(width: 40, height: 40).background(.white.opacity(0.05))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }.disabled(contractQty <= 1)
                                    Text("\(contractQty)")
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white).frame(width: 48)
                                    Button { if contractQty < maxSellable { contractQty += 1 } } label: {
                                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(contractQty < maxSellable ? Color.pink : .white.opacity(0.2))
                                            .frame(width: 40, height: 40)
                                            .background(contractQty < maxSellable ? Color.pink.opacity(0.12) : Color.white.opacity(0.04))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }.disabled(contractQty >= maxSellable)
                                }
                            }
                        }
                        .padding(18).glassCard(cornerRadius: 22).padding(.horizontal, 20)

                        // Proceeds summary
                        VStack(spacing: 14) {
                            HStack {
                                Text("Premium per share").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text(String(format: "$%.2f", contract.currentValue))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                            HStack {
                                Text("Contracts × 100 shares").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                                Spacer()
                                Text("\(contractQty) × 100")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }
                            Divider().background(.white.opacity(0.08))
                            HStack {
                                Text("Estimated proceeds").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                Spacer()
                                Text(fmt.string(from: NSNumber(value: proceeds)) ?? "")
                                    .font(.system(size: 20, weight: .light, design: .rounded)).foregroundStyle(Color.teal)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: contractQty)
                        .padding(18).glassCard(cornerRadius: 22).padding(.horizontal, 20)

                        Button { onExecute(contractQty) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Confirm Sell")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Color.pink).clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .padding(.horizontal, 20)

                        Spacer(minLength: 20)
                    }
                }
            }
        }
    }
}

#Preview {
    AssetDetailsView(
        asset: AssetInfo(
            ticker: "SPY",
            name: "S&P 500 ETF",
            annualReturn: 0.10,
            annualVolatility: 0.15,
            category: .equity
        )
    )
    .environmentObject(AppState())
}
