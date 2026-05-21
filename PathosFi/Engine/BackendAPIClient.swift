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

    // MARK: - Private Helpers

    enum APIError: Error {
        case networkFailure
        case decodingFailure
        case serverError(Int)
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
}
