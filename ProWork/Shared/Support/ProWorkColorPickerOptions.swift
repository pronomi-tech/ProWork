//  ProWorkColorPickerOptions.swift
//  ProWork
//  Created by Pronomi.
// TaskCategoryFormView and TodoStatusFormView declared the
//  same 10-entry color list inline. Two problems with the duplication:
//   1. A designer adding/renaming a color had to touch two files in
//      lockstep — at least one form drifted in every iteration.
//   2. The localizer keys (`common.color.*`) were hand-written in two
//      places, so a typo could silently leave one form rendering the
//      Turkish fallback.
//  The shared factory exposes the canonical 10 colors that
//  Migration001 / Migration002 install for system categories +
//  statuses; both forms route through it and stay in sync.

import Foundation

enum ProWorkColorPickerOptions {
    /// (id, localizerKey, fallback) tuples — kept as a typed list
    /// rather than a Dictionary so iteration order matches the picker
    /// order designers signed off on.
    static let canonical: [(id: String, key: String, fallback: String)] = [
        ("blue", "common.color.blue", "Mavi"),
        ("orange", "common.color.orange", "Turuncu"),
        ("purple", "common.color.purple", "Mor"),
        ("cyan", "common.color.cyan", "Camgöbeği"),
        ("red", "common.color.red", "Kırmızı"),
        ("green", "common.color.green", "Yeşil"),
        ("yellow", "common.color.yellow", "Sarı"),
        ("indigo", "common.color.indigo", "İndigo"),
        ("mint", "common.color.mint", "Mint"),
        ("gray", "common.color.gray", "Gri")
    ]

    static func searchPickerOptions(localizer: AppSettingsStore) -> [SearchPickerOption] {
        canonical.map { entry in
            SearchPickerOption(
                id: entry.id,
                title: localizer.localized(entry.key, defaultValue: entry.fallback)
            )
        }
    }
}
