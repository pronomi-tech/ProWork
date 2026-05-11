//
//  VatRateLabel.swift
//  ProWork
//
//  Created by Pronomi.
//
//  Picker'larda ve listelerde KDV tanımlarını tutarlı biçimde göstermek için.
//

import Foundation

struct VatRatePickerContent {
    let options: [SearchPickerOption]
    let defaultPlaceholder: String
}

enum VatRateLabel {
    /// "% 20" veya "Muaf"
    static func display(_ rate: VatRate, settingsStore: AppSettingsStore) -> String {
        if rate.isExempt {
            return settingsStore.localized("vat.exemptBadge", defaultValue: "Muaf")
        }
        let percent = NSDecimalNumber(decimal: rate.rate * 100).stringValue
        return "% \(percent)"
    }

    /// "Standart — % 20" veya "Muafiyet — Muaf"
    static func full(_ rate: VatRate, settingsStore: AppSettingsStore) -> String {
        "\(rate.name) — \(display(rate, settingsStore: settingsStore))"
    }

    static func pickerContent(
        organizationId: String,
        settingsStore: AppSettingsStore,
        repository: VatRateRepository = VatRateRepository()
    ) -> VatRatePickerContent {
        let rates = (try? repository.fetchAll(organizationId: organizationId)) ?? []
        let options = rates
            .filter(\.isActive)
            .map { rate in
                SearchPickerOption(
                    id: rate.id,
                    title: full(rate, settingsStore: settingsStore),
                    subtitle: rate.isDefault
                        ? settingsStore.localized("vat.column.default", defaultValue: "Varsayılan")
                        : nil
                )
            }

        let defaultPlaceholder: String
        if let defaultRate = rates.first(where: \.isDefault) {
            defaultPlaceholder = String(
                format: settingsStore.localized("vat.picker.useDefault.named", defaultValue: "Varsayılan KDV (%@)"),
                display(defaultRate, settingsStore: settingsStore)
            )
        } else {
            defaultPlaceholder = settingsStore.localized("vat.picker.useDefault", defaultValue: "Varsayılan KDV")
        }

        return VatRatePickerContent(options: options, defaultPlaceholder: defaultPlaceholder)
    }

    static func nonDefaultSelectionLabels(
        rates: [VatRate],
        settingsStore: AppSettingsStore
    ) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: rates.compactMap { rate in
                guard !rate.isDefault else {
                    return nil
                }
                return (rate.id, full(rate, settingsStore: settingsStore))
            }
        )
    }
}
