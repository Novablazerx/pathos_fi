import Foundation

/// API client for the PathosFi Python backend.
/// Handles complex Black-Scholes calculations and AI-driven predictive volatility
/// that are offloaded from the on-device Accelerate engine.
actor BackendAPIClient {

    // MARK: - Configuration

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
            ?? URL(string: "http://127.0.0.1:8000/v1")
            ?? URL(fileURLWithPath: "/") // static URL string is valid; fallback silences compiler only
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Predictive Volatility

    struct VolatilityRequest: Codable {
        let tickers: [String]
        let horizon: String  // "1m" | "6m" | "1y" | "5y"
    }

    struct VolatilityResponse: Codable {
        let multiplier: Double         // forward-looking vol multiplier vs historical
        let sentimentScore: Double     // -1.0 (bearish) to 1.0 (bullish)
        let vixForward: Double         // predicted VIX at horizon
        let confidenceInterval: [Double]
    }

    /// Fetch AI-predicted forward-looking volatility from the backend.
    /// Falls back to a multiplier of 1.0 (historical vol) on network failure.
    func fetchPredictedVolatility(
        tickers: [String],
        horizon: TimeHorizon
    ) async -> VolatilityResponse {
        let request = VolatilityRequest(tickers: tickers, horizon: horizon.rawValue)
        guard let data = try? await post(endpoint: "volatility/predict", body: request),
              let response = try? JSONDecoder().decode(VolatilityResponse.self, from: data)
        else {
            // Graceful degradation — use historical volatility
            return VolatilityResponse(multiplier: 1.0, sentimentScore: 0.0,
                                      vixForward: 20.0, confidenceInterval: [0.8, 1.2])
        }
        return response
    }

    // MARK: - Black-Scholes (Server-side)

    struct PutHedgeRequest: Codable {
        let underlyingTicker: String
        let portfolioValue: Double
        let maxLossPercent: Double
        let horizon: Double              // years
        let riskFreeRate: Double
        let impliedVolatility: Double
    }

    struct PutHedgeResponse: Codable {
        let strikePriceRecommended: Double
        let putPricePerContract: Double
        let delta: Double
        let theta: Double                // daily decay $
        let contractsNeeded: Int
        let totalHedgeCost: Double
        let effectiveExpectedReturn: Double  // after theta drag
    }

    /// Request server-side Black-Scholes put sizing.
    func fetchPutHedgeRecommendation(request: PutHedgeRequest) async throws -> PutHedgeResponse {
        guard let data = try? await post(endpoint: "options/put-hedge", body: request) else {
            throw APIError.networkFailure
        }
        return try JSONDecoder().decode(PutHedgeResponse.self, from: data)
    }

    // MARK: - Portfolio Simulation

    struct AssetPosition: Codable {
        let ticker: String
        let type: String        // "equity" or "option"
        let shares: Double?
        let contract: String?   // "call" or "put"
        let strike: Double?
        let expiry: String?     // ISO-8601 date, e.g. "2026-06-19"
        let quantity: Int?
    }

    struct PortfolioSimRequest: Codable {
        let portfolioId: String
        let horizonDays: Int    // clamped to 1-252 before sending
        let assets: [AssetPosition]

        enum CodingKeys: String, CodingKey {
            case portfolioId  = "portfolio_id"
            case horizonDays  = "horizon_days"
            case assets
        }
    }

    struct HistogramData: Codable {
        let bins: [Double]
        let probabilities: [Double]
    }

    struct PortfolioSimResponse: Codable {
        let portfolioId: String
        let currentValue: Double
        let expectedMeanValueT30: Double
        let valueAtRisk95: Double
        let expectedShortfall95: Double
        let distributionHistogram: HistogramData
        let bnnModelUsed: Bool

        enum CodingKeys: String, CodingKey {
            case portfolioId           = "portfolio_id"
            case currentValue          = "current_value"
            case expectedMeanValueT30  = "expected_mean_value_t30"
            case valueAtRisk95         = "value_at_risk_95"
            case expectedShortfall95   = "expected_shortfall_95"
            case distributionHistogram = "distribution_histogram"
            case bnnModelUsed          = "bnn_model_used"
        }
    }

    /// POST /v1/portfolio/simulate — runs 10 000-path Monte Carlo + BNN drift/vol on the backend.
    func fetchPortfolioSimulation(request: PortfolioSimRequest) async throws -> PortfolioSimResponse {
        guard let data = try? await post(endpoint: "portfolio/simulate", body: request) else {
            throw APIError.networkFailure
        }
        return try JSONDecoder().decode(PortfolioSimResponse.self, from: data)
    }

    // MARK: - RLHF Sync

    struct InteractionBatch: Codable {
        let userId: String
        let interactions: [InteractionEvent]
    }

    struct InteractionEvent: Codable {
        let pairName: String
        let hedgeType: String
        let action: String
        let timestamp: Date
    }

    /// Upload user interaction events to the backend RLHF training pipeline.
    func syncInteractions(userId: String, events: [InteractionEvent]) async {
        let batch = InteractionBatch(userId: userId, interactions: events)
        _ = try? await post(endpoint: "rlhf/sync", body: batch)
    }

    // MARK: - User & Portfolio Data

    struct UserRecord: Codable {
        let userId: Int
        let username: String
        let email: String
        let riskProfile: String?
        let cashBalance: Double

        enum CodingKeys: String, CodingKey {
            case userId      = "user_id"
            case username
            case email
            case riskProfile = "risk_profile"
            case cashBalance = "cash_balance"
        }
    }

    struct AssetOut: Codable {
        let assetId: Int
        let ticker: String
        let assetName: String?
        let assetType: String?
        let sector: String?
        let prevDayPrice: PriceRow?
        let currentDayPrice: PriceRow?

        enum CodingKeys: String, CodingKey {
            case assetId       = "asset_id"
            case ticker
            case assetName     = "asset_name"
            case assetType     = "asset_type"
            case sector
            case prevDayPrice    = "prev_day_price"
            case currentDayPrice = "current_day_price"
        }
    }

    struct UserAssetOut: Codable {
        let assetId: Int
        let ticker: String
        let assetName: String?
        let quantity: Double
        let avgCostBasis: Double?

        enum CodingKeys: String, CodingKey {
            case assetId      = "asset_id"
            case ticker
            case assetName    = "asset_name"
            case quantity
            case avgCostBasis = "avg_cost_basis"
        }
    }

    struct OptionOut: Codable {
        let optionId: Int
        let assetId: Int
        let optionType: String?
        let strikePrice: Double?
        let expiryDate: String?
        let premium: Double?
        let impliedVolatility: Double?
        let contractSize: Int
        let contractsHeld: Int?   // returned by user-scoped endpoints

        enum CodingKeys: String, CodingKey {
            case optionId         = "option_id"
            case assetId          = "asset_id"
            case optionType       = "option_type"
            case strikePrice      = "strike_price"
            case expiryDate       = "expiry_date"
            case premium
            case impliedVolatility = "implied_volatility"
            case contractSize     = "contract_size"
            case contractsHeld    = "contracts_held"
        }
    }

    func fetchUser(username: String) async throws -> UserRecord {
        let data = try await get(endpoint: "users/by-username/\(username)")
        return try JSONDecoder().decode(UserRecord.self, from: data)
    }

    func fetchAllAssets() async throws -> [AssetOut] {
        let data = try await get(endpoint: "assets")
        return try JSONDecoder().decode([AssetOut].self, from: data)
    }

    func fetchUserAssets(userId: Int) async throws -> [UserAssetOut] {
        let data = try await get(endpoint: "users/\(userId)/assets")
        return try JSONDecoder().decode([UserAssetOut].self, from: data)
    }

    func fetchOptions(assetId: Int, userId: Int) async throws -> [OptionOut] {
        let data = try await get(endpoint: "assets/\(assetId)/options/users/\(userId)")
        return try JSONDecoder().decode([OptionOut].self, from: data)
    }

    func updateUserRiskProfile(userId: Int, riskProfile: String) async throws {
        struct Body: Encodable { let risk_profile: String }
        _ = try await put(endpoint: "users/\(userId)", body: Body(risk_profile: riskProfile))
    }

    func updateCashBalance(userId: Int, cashBalance: Double) async throws {
        struct Body: Encodable { let cash_balance: Double }
        _ = try await put(endpoint: "users/\(userId)", body: Body(cash_balance: cashBalance))
    }

    func fetchAllAssetOptions(assetId: Int) async throws -> [OptionOut] {
        let data = try await get(endpoint: "assets/\(assetId)/options")
        return try JSONDecoder().decode([OptionOut].self, from: data)
    }

    // MARK: - Market Data

    struct PriceRow: Codable {
        let date: String
        let open: Double?
        let high: Double?
        let low: Double?
        let close: Double
        let adjClose: Double?
        let volume: Int?

        enum CodingKeys: String, CodingKey {
            case date, open, high, low, close
            case adjClose = "adj_close"
            case volume
        }
    }

    struct ForecastPoint: Codable {
        let date: String
        let price: Double
    }

    struct MarketDataResponse: Codable {
        let assetId: Int
        let ticker: String
        let priceHistory: [PriceRow]
        let historicalVolatility30d: Double?
        let priceForecast30d: [ForecastPoint]

        enum CodingKeys: String, CodingKey {
            case assetId = "asset_id"
            case ticker
            case priceHistory = "price_history"
            case historicalVolatility30d = "historical_volatility_30d"
            case priceForecast30d = "price_forecast_30d"
        }
    }

    func fetchMarketData(assetId: Int) async throws -> MarketDataResponse {
        let data = try await get(endpoint: "assets/\(assetId)/market-data")
        return try JSONDecoder().decode(MarketDataResponse.self, from: data)
    }

    func upsertUserAsset(userId: Int, assetId: Int, quantity: Double, avgCostBasis: Double?) async throws {
        struct Body: Encodable { let quantity: Double; let avg_cost_basis: Double? }
        _ = try await put(endpoint: "users/\(userId)/assets/\(assetId)",
                          body: Body(quantity: quantity, avg_cost_basis: avgCostBasis))
    }

    func deleteUserAsset(userId: Int, assetId: Int) async throws {
        try await delete(endpoint: "users/\(userId)/assets/\(assetId)")
    }

    func upsertUserOption(userId: Int, optionId: Int, contractsHeld: Int) async throws {
        struct Body: Encodable { let contracts_held: Int }
        _ = try await put(endpoint: "users/\(userId)/options/\(optionId)",
                          body: Body(contracts_held: contractsHeld))
    }

    func deleteUserOption(userId: Int, optionId: Int) async throws {
        try await delete(endpoint: "users/\(userId)/options/\(optionId)")
    }

    // MARK: - RL Portfolio Recommendation

    struct RLRecommendInput: Encodable {
        let risk_margin: Double
        let horizon_days: Int
    }

    enum RLStatus: String, Codable {
        case approved             = "approved"
        case rejectedFallbackHold = "rejected_fallback_hold"
    }

    enum RLTradeSide: String, Codable {
        case buy  = "buy"
        case sell = "sell"
        case hold = "hold"
    }

    enum RLContractType: String, Codable {
        case put  = "put"
        case call = "call"
    }

    struct RLTradeAction: Codable {
        let ticker: String
        let side: RLTradeSide
        let shares: Double
        let notionalUsd: Double

        enum CodingKeys: String, CodingKey {
            case ticker, side, shares
            case notionalUsd = "notional_usd"
        }
    }

    struct RLHedgeAction: Codable {
        let ticker: String
        let contractType: RLContractType
        let contracts: Int
        let strike: Double
        let expiry: String
        let premiumPerContract: Double
        let totalPremium: Double

        enum CodingKeys: String, CodingKey {
            case ticker
            case contractType       = "contract_type"
            case contracts, strike, expiry
            case premiumPerContract = "premium_per_contract"
            case totalPremium       = "total_premium"
        }
    }

    struct RLStressTest: Codable {
        let crashPct: Double
        let projectedWorstCaseValue: Double
        let projectedMaxLossUsd: Double
        let riskMargin: Double
        let marginBreach: Bool

        enum CodingKeys: String, CodingKey {
            case crashPct                = "crash_pct"
            case projectedWorstCaseValue = "projected_worst_case_value"
            case projectedMaxLossUsd     = "projected_max_loss_usd"
            case riskMargin              = "risk_margin"
            case marginBreach            = "margin_breach"
        }
    }

    struct RLRecommendResponse: Codable {
        let portfolioId: String
        let status: RLStatus
        let rationale: String
        let currentValue: Double
        let trades: [RLTradeAction]
        let hedges: [RLHedgeAction]
        let stressTest: RLStressTest
        let rlModelUsed: Bool

        enum CodingKeys: String, CodingKey {
            case portfolioId = "portfolio_id"
            case status, rationale
            case currentValue = "current_value"
            case trades, hedges
            case stressTest  = "stress_test"
            case rlModelUsed = "rl_model_used"
        }
    }

    /// POST /v1/rl-portfolio/users/{userId}/recommend — runs PPO policy to generate a trade/hedge plan.
    func fetchRLRecommendation(userId: Int, riskMargin: Double, horizonDays: Int = 30) async throws -> RLRecommendResponse {
        let body = RLRecommendInput(risk_margin: riskMargin, horizon_days: horizonDays)
        guard let data = try? await post(endpoint: "rl-portfolio/users/\(userId)/recommend", body: body) else {
            throw APIError.networkFailure
        }
        return try JSONDecoder().decode(RLRecommendResponse.self, from: data)
    }

    // MARK: - Private Helpers

    enum APIError: Error {
        case networkFailure
        case decodingFailure
        case serverError(Int)
    }

    private func get(endpoint: String) async throws -> Data {
        let base = baseURL.absoluteString
        let slash = base.hasSuffix("/") ? "" : "/"
        guard let url = URL(string: base + slash + endpoint) else { throw APIError.networkFailure }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        return data
    }

    private func post<T: Encodable>(endpoint: String, body: T) async throws -> Data {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        return data
    }

    private func patch<T: Encodable>(endpoint: String, body: T) async throws -> Data {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        urlRequest.httpMethod = "PATCH"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        return data
    }

    private func put<T: Encodable>(endpoint: String, body: T) async throws -> Data {
        let base = baseURL.absoluteString
        let slash = base.hasSuffix("/") ? "" : "/"
        guard let url = URL(string: base + slash + endpoint) else { throw APIError.networkFailure }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        return data
    }

    private func delete(endpoint: String) async throws {
        let base = baseURL.absoluteString
        let slash = base.hasSuffix("/") ? "" : "/"
        guard let url = URL(string: base + slash + endpoint) else { throw APIError.networkFailure }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
    }
}
