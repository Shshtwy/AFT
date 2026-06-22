import Foundation

enum TimeRemainingFormatter {
    static func string(_ seconds: Double?) -> String {
        guard let s = seconds, s.isFinite, s >= 0 else {
            return "Estimating time remaining…"
        }
        switch s {
        case ..<5:   return "Less than 5 seconds remaining"
        case ..<15:  return "Less than 15 seconds remaining"
        case ..<30:  return "Less than 30 seconds remaining"
        case ..<90:  return "About 1 minute remaining"
        case ..<3600:
            return "About \(Int((s / 60).rounded())) minutes remaining"
        case ..<5400:
            return "About 1 hour remaining"
        default:
            return "About \(Int((s / 3600).rounded())) hours remaining"
        }
    }
}
