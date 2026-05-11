//
//  SearchPickerOption.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

struct SearchPickerOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String?

    init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}
