import Foundation

/// Black-Scholes option pricing model for put-hedge recommendations.
/// Calculates option price, Delta (Δ), and Theta (Θ) for protective puts.
struct BlackScholesEngine {

    // MARK: - Option Price

    /// Price a European put option using Black-Scholes.
    /// - Parameters:
    ///   - S: Current underlying price
    ///   - K: Strike price
    ///   - T: Time to expiration in years
    ///   - r: Risk-free rate (annual, e.g. 0.05)
    ///   - sigma: Implied volatility (annual, e.g. 0.20)
    /// - Returns: Put option price per unit of underlying
    static func putPrice(S: Double, K: Double, T: Double, r: Double, sigma: Double) -> Double {
        guard T > 0, sigma > 0, S > 0, K > 0 else { return max(K - S, 0) }
        let d1 = (log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * sqrt(T))
        let d2 = d1 - sigma * sqrt(T)
        return K * exp(-r * T) * normalCDF(-d2) - S * normalCDF(-d1)
    }

    // MARK: - Greeks

    /// Delta (Δ) of a put option: rate of change of option price w.r.t. underlying price.
    /// Put delta is negative (–1 to 0); a delta of –0.5 means the put gains $0.50 per $1 fall.
    static func putDelta(S: Double, K: Double, T: Double, r: Double, sigma: Double) -> Double {
        guard T > 0, sigma > 0 else { return -1.0 }
        let d1 = (log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * sqrt(T))
        return normalCDF(d1) - 1.0
    }

    /// Theta (Θ) of a put option: daily time decay in dollars per unit underlying.
    static func putTheta(S: Double, K: Double, T: Double, r: Double, sigma: Double) -> Double {
        guard T > 0, sigma > 0 else { return 0 }
        let d1 = (log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * sqrt(T))
        let d2 = d1 - sigma * sqrt(T)
        let term1 = -(S * normalPDF(d1) * sigma) / (2 * sqrt(T))
        let term2 = r * K * exp(-r * T) * normalCDF(-d2)
        return (term1 + term2) / 365.0   // per calendar day
    }

    // MARK: - Hedge Sizing

    /// Calculate number of put contracts needed to delta-hedge a portfolio.
    /// Each standard equity option contract covers 100 shares.
    /// - Parameters:
    ///   - portfolioValue: Total portfolio value in dollars
    ///   - stockPrice:     Current price per share of underlying
    ///   - putDelta:       Delta of the selected put option (negative number)
    ///   - contractSize:   Shares per contract (default 100)
    /// - Returns: Number of put contracts to buy (rounded up for full coverage)
    static func contractsNeeded(
        portfolioValue: Double,
        stockPrice: Double,
        putDelta: Double,
        contractSize: Int = 100
    ) -> Int {
        guard putDelta != 0, stockPrice > 0 else { return 0 }
        let sharesEquivalent = portfolioValue / stockPrice
        let rawContracts = sharesEquivalent / (abs(putDelta) * Double(contractSize))
        guard rawContracts.isFinite else { return 0 }
        return rawContracts.rounded(.up).safeInt()
    }

    // MARK: - Standard Normal Helpers

    static func normalCDF(_ x: Double) -> Double {
        return 0.5 * erfc(-x / sqrt(2.0))
    }

    static func normalPDF(_ x: Double) -> Double {
        return exp(-0.5 * x * x) / sqrt(2.0 * .pi)
    }
}
