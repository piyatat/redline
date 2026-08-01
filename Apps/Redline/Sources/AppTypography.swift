import SwiftUI
import RedlineShared

enum AppTextStyle: Sendable {
    case largeTitle
    case title2
    case title3
    case headline
    case body
    case callout
    case caption
    case caption2
}

enum AppTypography {
    static func size(_ style: AppTextStyle, base: CGFloat) -> CGFloat {
        switch style {
        case .largeTitle: return base * 2.0
        case .title2: return base * 1.45
        case .title3: return base * 1.25
        case .headline: return base * 1.1
        case .body: return base
        case .callout: return base * 0.92
        case .caption: return base * 0.85
        case .caption2: return base * 0.75
        }
    }

    static func font(
        _ style: AppTextStyle,
        base: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size(style, base: base), weight: weight, design: design)
    }
}

private struct AppFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = CGFloat(AgentSettings.logFontSizeDefault)
}

extension EnvironmentValues {
    /// Preferred base text size in points (from Settings → Appearance).
    var appFontSize: CGFloat {
        get { self[AppFontSizeKey.self] }
        set { self[AppFontSizeKey.self] = newValue }
    }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.appFontSize) private var base
    var style: AppTextStyle
    var weight: Font.Weight
    var design: Font.Design

    func body(content: Content) -> some View {
        content.font(AppTypography.font(style, base: base, weight: weight, design: design))
    }
}

extension View {
    /// Font that scales with Settings → Appearance → App font size.
    func appFont(
        _ style: AppTextStyle,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(AppFontModifier(style: style, weight: weight, design: design))
    }

    /// Apply Redline’s global font-size setting to the view tree.
    func redlineAppTypography(fontSizePoints: Double) -> some View {
        let clamped = AgentSettings.clampedLogFontSize(fontSizePoints)
        return environment(\.appFontSize, CGFloat(clamped))
    }
}
