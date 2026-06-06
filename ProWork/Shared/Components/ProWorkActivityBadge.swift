//  ProWorkActivityBadge.swift
//  ProWork
//  Created by Pronomi.
//  Visually represents the `isActive` state in grid rows.
//  ortak badge. Eskiden her grid (Customers, VatRates, Holidays,
//  PriceLists, TaskCategories vb.) `Image(systemName: isActive ?
//  `"checkmark.circle.fill" : "xmark.circle")`. After Projects
//  grid'inde renkli nokta + lokalize ad pattern'ine (Aktif/Pasif/...)
//  migrated, a uniform look was needed across all grids —
//  bu component o pattern'i tek noktadan sunar.

import SwiftUI

struct ProWorkActivityBadge: View {
    let isActive: Bool

    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(
                isActive
                    ? settingsStore.localized("common.status.active", defaultValue: "Aktif")
                    : settingsStore.localized("common.status.inactive", defaultValue: "Pasif")
            )
            .proWorkTextStyle(.caption)
            .lineLimit(1)
        }
    }
}
