import Foundation

extension Double {
    /// Safely converts a Double to Int, returning a fallback if the value
    /// is NaN, infinite, or outside Int's representable range.
    ///
    /// Uses `Int(exactly:)` after truncating toward zero — **never** calls the
    /// trapping `Int(_: Double)` initializer. (Guards like `self <= Double(Int.max)`
    /// are unsafe because `Double(Int.max)` rounds upward past `Int.max`, so some
    /// finite doubles passed the old checks yet still trapped in `Int(self)`.)
    func safeInt(fallback: Int = 0) -> Int {
        guard self.isFinite else { return fallback }
        let towardZero = self >= 0 ? floor(self) : ceil(self)
        guard towardZero.isFinite else { return fallback }
        return Int(exactly: towardZero) ?? fallback
    }

    /// Returns the Double clamped to a finite value, replacing NaN/Infinity
    /// with the given fallback.
    func safeValue(fallback: Double = 0.0) -> Double {
        return self.isFinite ? self : fallback
    }

    /// Formats the Double as a percentage string safely.
    func safePercentString(decimals: Int = 1) -> String {
        let safe = self.safeValue()
        return String(format: "%.\(decimals)f", safe) + "%"
    }

    /// Formats the Double as a signed percentage string (e.g. "+8.2%" or "-3.1%").
    func safeSignedPercentString(decimals: Int = 1) -> String {
        let safe = self.safeValue()
        let sign = safe >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.\(decimals)f", safe))%"
    }
}
