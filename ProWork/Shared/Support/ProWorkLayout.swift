//
//  ProWorkLayout.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

enum ProWorkLayout {
    static func scale(using settingsStore: AppSettingsStore) -> CGFloat {
        settingsStore.settings.fontSize.scale
    }

    static func scaled(
        _ value: CGFloat,
        using settingsStore: AppSettingsStore
    ) -> CGFloat {
        value * scale(using: settingsStore)
    }
    
    static func formScale(using settingsStore: AppSettingsStore) -> CGFloat {
        let scale = settingsStore.settings.fontSize.scale

        switch settingsStore.settings.fontSize {
        case .small:
            return max(0.92, scale)
        case .normal:
            return 1.0
        case .large:
            return min(1.14, scale)
        case .extraLarge:
            return min(1.24, scale)
        }
    }

    static func formScaled(
        _ value: CGFloat,
        using settingsStore: AppSettingsStore
    ) -> CGFloat {
        value * formScale(using: settingsStore)
    }
}

private struct ProWorkScaledMetricModifier: ViewModifier {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let width: CGFloat?
    let height: CGFloat?
    let minWidth: CGFloat?
    let minHeight: CGFloat?
    let maxWidth: CGFloat?
    let maxHeight: CGFloat?
    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: scaledOptional(minWidth),
                maxWidth: scaledOptional(maxWidth),
                minHeight: scaledOptional(minHeight),
                maxHeight: scaledOptional(maxHeight),
                alignment: alignment
            )
            .frame(
                width: scaledOptional(width),
                height: scaledOptional(height),
                alignment: alignment
            )
    }

    private func scaledOptional(_ value: CGFloat?) -> CGFloat? {
        guard let value else {
            return nil
        }

        guard value.isFinite else {
            return value
        }

        return ProWorkLayout.scaled(value, using: settingsStore)
    }
}

extension View {
    func proWorkFrame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        modifier(
            ProWorkScaledMetricModifier(
                width: width,
                height: height,
                minWidth: minWidth,
                minHeight: minHeight,
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                alignment: alignment
            )
        )
    }
}
