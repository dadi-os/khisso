import SwiftUI

extension Font {
    /// The દાદી wordmark and other Gujarati display text, in the bundled Noto
    /// Sans Gujarati.
    static func wordmark(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Noto Sans Gujarati", fixedSize: size).weight(weight)
    }
}

/// dadi's motion, matching thaali's timings: springs for anything a finger
/// moves, the slow ease for content, and the breath for ambient pulses.
enum Motion {
    /// Content settling into place (thaali's 550 ms ease).
    static let settle = Animation.smooth(duration: 0.55)
    /// Controls and sheets.
    static let snap = Animation.snappy(duration: 0.32)
    /// A small celebratory bounce, for success only.
    static let pop = Animation.bouncy(duration: 0.5, extraBounce: 0.12)
    /// The ambient breath, 2.4 s each way.
    static let breath = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
}

/// Where Noto Sans Gujarati's ink sits in its line box, which is centered
/// 0.244 em above the baseline. Measured with CoreText: દાદી's ink, with its
/// tall ી, is centered 0.199 em above that, and a lone દ 0.0525 em above it.
enum GujaratiInk {
    case word
    case letter

    /// How far the ink's center sits above the line box's, per point of size.
    var lift: CGFloat {
        switch self {
        case .word: 0.199
        case .letter: 0.0525
        }
    }
}

extension View {
    /// Moves Gujarati text set at `size` down so its ink, not its line box, is
    /// what's centered.
    func inkCentered(_ ink: GujaratiInk, size: CGFloat) -> some View {
        offset(y: ink.lift * size)
    }
}
