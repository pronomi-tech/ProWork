//  ProWorkFieldContainer.swift
//  ProWork
//  Modifier shared across form fields (`ProWorkTextField`, `ProWorkSecureField`,
//  `ProWorkTextEditor`, `ProWorkDateField`, `ProWorkDateTimeField`,
//  `ProWorkSearchPickerField`) for a uniform background + border + corner
//  radius chain. Previously, the identical `.padding / .background /
//  .clipShape / .overlay(stroke)` was inlined across 6+ files.

import SwiftUI

/// `proWorkFieldContainer(...)` modifier. The parameters governing the
/// container's appearance ship with defaults; individual ones can be
/// overridden as needed. Fields whose border colour depends on state
/// (Date/Search picker etc.) pass `strokeColor` / `strokeLineWidth`.
struct ProWorkFieldContainerModifier: ViewModifier {
    let minHeight: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let backgroundOpacity: Double
    let alignment: Alignment
    let fillsWidth: Bool
    let strokeColor: AnyShapeStyle
    let strokeLineWidth: CGFloat

    @EnvironmentObject private var settingsStore: AppSettingsStore

    func body(content: Content) -> some View {
        let radius = ProWorkLayout.scaled(cornerRadius, using: settingsStore)
        let shape = RoundedRectangle(cornerRadius: radius)
        return content
            .padding(.horizontal, ProWorkLayout.scaled(horizontalPadding, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(verticalPadding, using: settingsStore))
            .frame(
                maxWidth: fillsWidth ? .infinity : nil,
                minHeight: ProWorkLayout.scaled(minHeight, using: settingsStore),
                alignment: alignment
            )
            .background(.background.opacity(backgroundOpacity))
            .clipShape(shape)
            .overlay(shape.stroke(strokeColor, lineWidth: strokeLineWidth))
    }
}

extension View {
    /// Applies the standard ProWork container appearance for form fields.
    /// Defaults match `ProWorkTextField`; override when a field type wants
    /// different padding / border values.
    func proWorkFieldContainer(
        minHeight: CGFloat = 40,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 6,
        cornerRadius: CGFloat = 10,
        backgroundOpacity: Double = 0.70,
        alignment: Alignment = .center,
        fillsWidth: Bool = false,
        strokeColor: AnyShapeStyle = AnyShapeStyle(.quaternary),
        strokeLineWidth: CGFloat = 1
    ) -> some View {
        modifier(
            ProWorkFieldContainerModifier(
                minHeight: minHeight,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                cornerRadius: cornerRadius,
                backgroundOpacity: backgroundOpacity,
                alignment: alignment,
                fillsWidth: fillsWidth,
                strokeColor: strokeColor,
                strokeLineWidth: strokeLineWidth
            )
        )
    }
}
