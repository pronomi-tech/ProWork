//  StringNilIfEmpty.swift
//  ProWork
//  Created by Pronomi.
// /: single home for the `nilIfEmpty` helper that
//  used to live as a `fileprivate extension String` in three (and
//  rising) form views. Each duplicate redefined the same `isEmpty ?
//  nil : self` contract; consolidating prevents drift if the empty-
//  trimming policy ever needs to change (e.g. collapse all-whitespace
//  to nil).

import Foundation

extension String {
    /// Returns `nil` when the receiver is empty; otherwise the
    /// receiver itself. Callers that also want to trim should pair
    /// with `.trimmingCharacters(in: .whitespacesAndNewlines)` first.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
