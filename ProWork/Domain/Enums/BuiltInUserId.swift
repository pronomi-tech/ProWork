//  BuiltInUserId.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Built-in user constant IDs.
/// Until auth is wired up, all createdBy/updatedBy fields point to the default Owner.
enum BuiltInUserId {
    nonisolated static let defaultOwner = "user_default_owner"
}
