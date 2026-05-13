import Foundation

struct TemporalResolution {
    let originalText: String
    let interpretation: TemporalInterpretation
    let confidence: Double
    let resolvedDate: Date?
    let resolvedDuration: TimeInterval?
    let resolvedClockTime: DateComponents?
    let formatAssumption: String?
    let alternativeCandidates: [TemporalResolution]
    let resolverPath: ResolverPath

    static func noSignal(for input: String) -> TemporalResolution {
        TemporalResolution(
            originalText: input,
            interpretation: .unknown,
            confidence: 0.0,
            resolvedDate: nil,
            resolvedDuration: nil,
            resolvedClockTime: nil,
            formatAssumption: nil,
            alternativeCandidates: [],
            resolverPath: .noSignal
        )
    }

    func withConfidence(_ newConfidence: Double, resolverPath newPath: ResolverPath) -> TemporalResolution {
        TemporalResolution(
            originalText: originalText,
            interpretation: interpretation,
            confidence: min(max(newConfidence, 0.0), 1.0),
            resolvedDate: resolvedDate,
            resolvedDuration: resolvedDuration,
            resolvedClockTime: resolvedClockTime,
            formatAssumption: formatAssumption,
            alternativeCandidates: alternativeCandidates,
            resolverPath: newPath
        )
    }
}
