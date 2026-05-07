import Foundation
import Accelerate

/// Core Monte Carlo simulation engine.
/// Uses the Accelerate framework for vectorised arithmetic (vDSP) to run
/// 10,000 Geometric Brownian Motion paths efficiently on-device.
struct MonteCarloEngine {

    // MARK: - Constants

    static let simulationCount: Int = 10_000
    static let pathSteps: Int = 252          // trading days per year

    // MARK: - Public API

    /// Run a full simulation for a two-asset (primary + hedge) portfolio.
    static func simulate(
        primaryWeight: Double,
        hedgeWeight: Double,
        primary: AssetInfo,
        hedge: AssetInfo,
        horizon: Double,
        maxLossLimit: Double,
        predictedVolatilityMultiplier: Double = 1.0
    ) -> SimulationResult {

        // Guard against degenerate inputs
        let safeHorizon    = max(horizon, 1.0 / 365.0)
        let safeMultiplier = max(0.1, min(predictedVolatilityMultiplier, 5.0))
        let safeMaxLoss    = max(0.001, min(maxLossLimit, 0.999))

        let steps = max(1, (safeHorizon * Double(pathSteps)).safeInt())
        let dt    = safeHorizon / Double(steps)

        // Clamp volatilities — very high vol (e.g. SQQQ 0.65) can produce
        // exp() overflow with extreme normal draws; cap at 2.0 (200% annual vol).
        let sigmaA = min(primary.annualVolatility * safeMultiplier, 2.0)
        let sigmaH = min(hedge.annualVolatility   * safeMultiplier, 2.0)
        let muA    = max(-2.0, min(primary.annualReturn, 2.0))
        let muH    = max(-2.0, min(hedge.annualReturn,   2.0))

        var finalReturns = [Double](repeating: 0.0, count: simulationCount)
        var samplePaths  = [[Double]]()
        let capturePaths = 200

        // --- GBM path generation ---
        for sim in 0 ..< simulationCount {
            var pathValues = [Double]()
            if sim < capturePaths {
                pathValues.reserveCapacity(steps + 1)
                pathValues.append(1.0)
            }

            var priceA = 1.0
            var priceH = 1.0

            for _ in 0 ..< steps {
                let zA = sampleStandardNormal()
                let zH = sampleStandardNormal()

                // Geometric Brownian Motion: S(t+dt) = S(t) * exp((mu - sigma^2/2)dt + sigma*sqrt(dt)*Z)
                // Clamp the exponent to [-10, 10] to prevent exp() overflow/underflow
                let exponentA = (muA - 0.5 * sigmaA * sigmaA) * dt + sigmaA * sqrt(dt) * zA
                let exponentH = (muH - 0.5 * sigmaH * sigmaH) * dt + sigmaH * sqrt(dt) * zH

                priceA *= exp(max(-10.0, min(exponentA, 10.0)))
                priceH *= exp(max(-10.0, min(exponentH, 10.0)))

                // Guard against NaN/Infinity before storing
                if priceA.isNaN || priceA.isInfinite { priceA = 0.0 }
                if priceH.isNaN || priceH.isInfinite { priceH = 0.0 }

                if sim < capturePaths {
                    let portfolioValue = primaryWeight * priceA + hedgeWeight * priceH
                    pathValues.append(portfolioValue)
                }
            }

            let finalPortfolio = primaryWeight * priceA + hedgeWeight * priceH
            let finalReturn    = finalPortfolio - 1.0
            finalReturns[sim]  = finalReturn.isFinite ? finalReturn : 0.0

            if sim < capturePaths {
                samplePaths.append(pathValues)
            }
        }

        // --- Compute statistics using vDSP ---
        let sortedReturns = finalReturns.sorted()

        let var95Index = max(0, min((0.05 * Double(simulationCount)).safeInt(), simulationCount - 1))
        let var95      = sortedReturns[var95Index]

        var mean = 0.0
        vDSP_meanvD(finalReturns, 1, &mean, vDSP_Length(simulationCount))
        if !mean.isFinite { mean = 0.0 }

        let threshold       = -safeMaxLoss
        let tailCount       = sortedReturns.filter { $0 < threshold }.count
        let profitCount     = sortedReturns.filter { $0 > 0 }.count
        let acceptableCount = max(0, simulationCount - tailCount - profitCount)

        let tailRisk   = Double(tailCount)       / Double(simulationCount) * 100.0
        let upside     = Double(profitCount)     / Double(simulationCount) * 100.0
        let acceptable = Double(acceptableCount) / Double(simulationCount) * 100.0

        return SimulationResult(
            upsidePercent:     upside.isFinite     ? upside     : 0.0,
            acceptablePercent: acceptable.isFinite ? acceptable : 0.0,
            tailRiskPercent:   tailRisk.isFinite   ? tailRisk   : 0.0,
            var95:             (var95 * 100.0).isFinite  ? var95 * 100.0  : 0.0,
            expectedReturn:    (mean  * 100.0).isFinite  ? mean  * 100.0  : 0.0,
            simulatedPaths:    samplePaths
        )
    }

    // MARK: - Portfolio Variance (Modern Portfolio Theory)

    static func portfolioVariance(
        wA: Double, sigmaA: Double,
        wH: Double, sigmaH: Double,
        correlation rho: Double
    ) -> Double {
        let termA   = wA * wA * sigmaA * sigmaA
        let termH   = wH * wH * sigmaH * sigmaH
        let termCov = 2 * wA * wH * sigmaA * sigmaH * rho
        return termA + termH + termCov
    }

    static func portfolioVolatility(
        wA: Double, sigmaA: Double,
        wH: Double, sigmaH: Double,
        correlation rho: Double
    ) -> Double {
        sqrt(portfolioVariance(wA: wA, sigmaA: sigmaA,
                               wH: wH, sigmaH: sigmaH,
                               correlation: rho))
    }

    // MARK: - Private Helpers

    /// Box-Muller transform — clamp output to +/-6 sigma to eliminate extreme
    /// draws that cause exp() to overflow with high-volatility assets like SQQQ.
    private static func sampleStandardNormal() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne ... 1.0)
        let u2 = Double.random(in: 0.0 ..< 1.0)
        let z  = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        return max(-6.0, min(z, 6.0))
    }
}
