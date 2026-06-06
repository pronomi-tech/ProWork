//  BillingRunsHeader.swift
//  ProWork
//  Top bar of BillingRunsView: title + subtitle + "new run" button.
//  Extracted from BillingRunsView.

import SwiftUI

struct BillingRunsHeader: View {
    let selectedRunIsDraft: Bool
    let onCreate: () -> Void

    @EnvironmentObject private var settingsStore: AppSettingsStore

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("billing.title", defaultValue: "Hizmet Dökümleri"))
                    .proWorkTextStyle(.largeTitle)
                Text(localized("billing.subtitle", defaultValue: "Dönem bazlı hizmet dökümü kayıtlarını yönetin, kesinleştirin, dışa aktarın ve ödeme takibi yapın."))
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // The if/else used to duplicate the entire Button
            // declaration just to flip `.bordered` ↔ `.borderedProminent`.
            // SwiftUI lets us compose the style off a single Button, so
            // the label/action stay shared and a future copy
            // change touches one site.
            Button(action: onCreate) {
                ProWorkButtonLabel(title: localized("billing.action.newRun", defaultValue: "Yeni Döküm"), systemImage: "plus")
            }
            .modifier(NewRunButtonStyleModifier(prominent: !selectedRunIsDraft))
            .controlSize(.large)
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
    }
}

/// Picks `.borderedProminent` for the primary-CTA state and
/// `.bordered` for the secondary state without duplicating the Button.
private struct NewRunButtonStyleModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
