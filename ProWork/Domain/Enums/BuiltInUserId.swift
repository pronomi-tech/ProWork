//
//  BuiltInUserId.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Yerleşik kullanıcı sabit ID'leri.
/// Auth devreye girene kadar tüm createdBy/updatedBy alanları default Owner'a yazar.
enum BuiltInUserId {
    nonisolated static let defaultOwner = "user_default_owner"
}
