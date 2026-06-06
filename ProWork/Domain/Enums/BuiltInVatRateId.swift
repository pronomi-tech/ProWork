//  BuiltInVatRateId.swift
//  ProWork
//  Created by Pronomi.
// stable identifiers for the system-seeded VAT rate rows.
//  Lives in `Domain/Enums/` alongside `BuiltInOrganizationId`,
//  `BuiltInUserId`, `BuiltInTodoStatusId`; previously buried at the
//  bottom of `Domain/Models/VatRate.swift` which made the convention
//  inconsistent.

import Foundation

enum BuiltInVatRateId {
    nonisolated static let defaultStandard = "vat_rate_default"
    nonisolated static let exempt = "vat_rate_exempt"
}
