//  VatRateLabel.swift
//  ProWork
//  Created by Pronomi.
//  Displays VAT definitions consistently in pickers and lists.

import Foundation
import os

struct VatRatePickerContent {
    let options: [SearchPickerOption]
    let defaultPlaceholder: String
}

enum VatRateLabel {
    // Instead of passing AppSettingsStore as a parameter, we go directly
    // to ProWorkLocalizer.shared. `AppSettingsStore.localized` is already
    // a pass-through to that shared instance — the store added nothing
    // but an extra dependency and was leaking a SwiftUI type into
    // ViewModel signatures.
    private static func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    /// "% 20" or "Muaf"
    static func display(_ rate: VatRate) -> String {
        if rate.isExempt {
            return localized("vat.exemptBadge", defaultValue: "Muaf")
        }
        let percent = NSDecimalNumber(decimal: rate.rate * 100).stringValue
        return "% \(percent)"
    }

    /// "Standart — % 20" or "Muafiyet — Muaf"
    static func full(_ rate: VatRate) -> String {
        "\(rate.name) — \(display(rate))"
    }

    /// `repository` is now a required parameter. The
    /// `AppServices.shared` default short-circuited dependency
    /// injection — tests passing a substitute `AppServices` would
    /// still get the singleton repository, masking the override.
    /// Callers now supply the repository explicitly (typically via
    /// `services.vatRateRepository`).
    ///
    /// Fetch errors no longer pass silently: we log and leave the picker
    /// empty, but the error is visible in Console.app. The picker UI has
    /// no error-banner channel, so log + empty fallback was chosen over
    /// an inline raise.
    static func pickerContent(
        organizationId: String,
        repository: VatRateRepository
    ) -> VatRatePickerContent {
        let rates: [VatRate]
        do {
            rates = try repository.fetchAll(organizationId: organizationId)
        } catch {
            ProWorkLog.app.error(
                "VatRateLabel.pickerContent fetch failed for organization \(organizationId, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            rates = []
        }
        let options = rates
            .filter(\.isActive)
            .map { rate in
                SearchPickerOption(
                    id: rate.id,
                    title: full(rate),
                    subtitle: rate.isDefault
                        ? localized("vat.column.default", defaultValue: "Varsayılan")
                        : nil
                )
            }

        let defaultPlaceholder: String
        if let defaultRate = rates.first(where: \.isDefault) {
            defaultPlaceholder = String(
                format: localized("vat.picker.useDefault.named", defaultValue: "Varsayılan KDV (%@)"),
                display(defaultRate)
            )
        } else {
            defaultPlaceholder = localized("vat.picker.useDefault", defaultValue: "Varsayılan KDV")
        }

        return VatRatePickerContent(options: options, defaultPlaceholder: defaultPlaceholder)
    }

    static func nonDefaultSelectionLabels(rates: [VatRate]) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: rates.compactMap { rate in
                guard !rate.isDefault else {
                    return nil
                }
                return (rate.id, full(rate))
            }
        )
    }
}
