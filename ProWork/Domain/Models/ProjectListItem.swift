//  ProjectListItem.swift
//  ProWork
//  Created by Pronomi.

import Foundation

struct ProjectListItem: Identifiable, Hashable {
    let id: String
    var customerId: String
    var customerName: String
    var name: String
    var code: String?
    var status: String
    var defaultServiceType: String?
    var defaultMinBillingMinutes: Int?
    var billingWindowMode: BillingWindowMode?
    var vatRateId: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}
