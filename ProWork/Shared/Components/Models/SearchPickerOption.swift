//  SearchPickerOption.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Canonical `(id, title, subtitle?)` shape. Five callers (
/// `PickerOption`, `CustomerOption`, `TodoFormSelectOption`,
/// `FilterOption`, `WorkSessionFilterOption`) all redeclared the same
/// fields with the same semantics; flagged the divergence
/// risk. Now each call site keeps its local typealias for readability
/// while the underlying type stays one struct (`SearchPickerOption`).
/// `Hashable` was added because some callers passed the struct into
/// Picker(selection:) which requires Hashable.
struct SearchPickerOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?

    init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

extension SearchPickerOption {
    /// Build "minimum billing minutes" picker options from a list of
    /// minute values plus a localized label for the "0" sentinel.
    /// (DRY): both CustomerFormView and ProjectFormView
    /// inlined essentially the same map, just with different value sets
    /// and different "0" semantics ("No Minimum Time" vs "Use Customer
    /// Setting"). Both forms now route through this helper so the
    /// minutes-suffix logic can't drift between them.
    static func minimumBillingMinutes(
        values: [Int],
        zeroTitle: String,
        minutesFormat: String
    ) -> [SearchPickerOption] {
        values.map { minutes in
            SearchPickerOption(
                id: String(minutes),
                title: minutes == 0 ? zeroTitle : String(format: minutesFormat, minutes)
            )
        }
    }
}
