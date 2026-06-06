//  FormSheetSize.swift
//  ProWork
//  Created by Pronomi.
// /
// every form sheet was passing its (width, height) pair as
//  inline literals. Two problems with that:
//   1. Magic numbers — readers can't tell at a glance whether 580×780
//      is the "compact form" footprint or the "detail edit" footprint.
//   2. Layout drift — a designer rebalance had to touch each call site
//      individually, and at least one form fell out of sync per
//      iteration.
//  The enum below names each historical footprint so future edits live
//  in one place. The point sizes match the previous literals exactly,
//  preserving every form's current look.

import CoreGraphics

enum FormSheetSize {
    /// Named (width, height) for every form sheet in the app. Heights
    /// were tuned individually during the design pass; widths cluster
    /// into four tiers (540 / 560 / 580-680 / 760-980) that match the
    /// content density rather than any free-form choice. Adding a new
    /// form should pick an existing tier when its width matches and
    /// only declare a new entry when truly novel.
    static let exchangeRateForm = CGSize(width: 540, height: 500)
    static let taskCategoryForm = CGSize(width: 540, height: 480)
    static let holidayForm = CGSize(width: 560, height: 500)
    static let vatRateForm = CGSize(width: 560, height: 460)
    static let paymentForm = CGSize(width: 560, height: 580)
    static let customerForm = CGSize(width: 580, height: 780)
    static let projectForm = CGSize(width: 580, height: 710)
    static let todoStatusForm = CGSize(width: 640, height: 640)
    static let todoForm = CGSize(width: 680, height: 860)
    static let workSessionForm = CGSize(width: 760, height: 768)
    static let todoTimeSessionsForm = CGSize(width: 760, height: 620)
    static let billingRunCreate = CGSize(width: 980, height: 860)
}
