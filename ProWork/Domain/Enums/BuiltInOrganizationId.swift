//
//  BuiltInOrganizationId.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

/// Yerleşik organization sabit ID'leri.
/// Sunucu sync devreye girene kadar tek default org üzerinde çalışılır.
enum BuiltInOrganizationId {
    nonisolated static let `default` = "org_default"
}
