//  ProWorkFonts.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

private struct ProWorkFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = AppFontSizeOption.normal.scale
}

extension EnvironmentValues {
    var proWorkFontScale: CGFloat {
        get { self[ProWorkFontScaleKey.self] }
        set { self[ProWorkFontScaleKey.self] = newValue }
    }
}

enum ProWorkFonts {
    static func scaledSize(
        _ size: CGFloat,
        using settingsStore: AppSettingsStore
    ) -> CGFloat {
        size * settingsStore.settings.fontSize.scale
    }

    static func scaledSize(
        _ size: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        size * scale
    }

    static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        using settingsStore: AppSettingsStore
    ) -> Font {
        .system(
            size: scaledSize(size, using: settingsStore),
            weight: weight,
            design: design
        )
    }

    static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        scale: CGFloat
    ) -> Font {
        .system(
            size: scaledSize(size, scale: scale),
            weight: weight,
            design: design
        )
    }
}

enum ProWorkTextStyle {
    case caption2
    case caption
    case footnote
    case callout
    case body
    case headline
    case title3
    case title2
    case title
    case largeTitle

    var baseSize: CGFloat {
        switch self {
        case .caption2:
            return 11
        case .caption:
            return 12
        case .footnote:
            return 13
        case .callout:
            return 14
        case .body:
            return 15
        case .headline:
            return 17
        case .title3:
            return 20
        case .title2:
            return 22
        case .title:
            return 28
        case .largeTitle:
            return 34
        }
    }

    var defaultWeight: Font.Weight {
        switch self {
        case .headline:
            return .semibold
        case .title3, .title2, .title, .largeTitle:
            return .bold
        default:
            return .regular
        }
    }
}

private struct ProWorkFontModifier: ViewModifier {
    @Environment(\.proWorkFontScale) private var fontScale

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(
            ProWorkFonts.font(
                size: size,
                weight: weight,
                design: design,
                scale: fontScale
            )
        )
    }
}

private struct ProWorkTextStyleModifier: ViewModifier {
    @Environment(\.proWorkFontScale) private var fontScale

    let style: ProWorkTextStyle
    let weight: Font.Weight?
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(
            ProWorkFonts.font(
                size: style.baseSize,
                weight: weight ?? style.defaultWeight,
                design: design,
                scale: fontScale
            )
        )
    }
}

extension View {
    func proWorkFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(
            ProWorkFontModifier(
                size: size,
                weight: weight,
                design: design
            )
        )
    }

    func proWorkTextStyle(
        _ style: ProWorkTextStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        modifier(
            ProWorkTextStyleModifier(
                style: style,
                weight: weight,
                design: design
            )
        )
    }

    func proWorkFontScale(_ scale: CGFloat) -> some View {
        environment(\.proWorkFontScale, scale)
    }
}
