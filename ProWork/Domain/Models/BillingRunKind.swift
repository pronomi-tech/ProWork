//  BillingRunKind.swift
//  ProWork
//  Created by Pronomi.
//  Type-safe alternative: previously, three different calculation modes
//  (`livePreview`, `draftPreview`, and the persisted `draft` / `final`) were
//  distinguished by `runId == "preview"` / `"draft-preview"` string constants;
//  they're now modelled by an enum. The emitted `BillingReportLine.runId`
//  field is derived from the same source — the magic strings are centralised.

import Foundation

enum BillingRunKind: Hashable {
    /// UI-side preview shown before any DB record exists.
    /// Open (endedAt = NULL) sessions are included.
    case livePreview
    /// The set of lines computed while creating a draft (closed
    /// sessions only). The resulting `runId` uses the "draft-preview"
    /// string so adjacent systems can recognize it even without an id.
    case draftPreview
    /// Persisted draft record.
    case draft(id: String)
    /// Persisted final (locked) record.
    case final(id: String)

    /// Value written to `BillingReportLine.runId`. For preview kinds,
    /// the "preview"/"draft-preview" constants are kept — they're never
    /// written to the DB and serve only to distinguish in-memory.
    var lineRunId: String {
        switch self {
        case .livePreview: return Self.livePreviewRunId
        case .draftPreview: return Self.draftPreviewRunId
        case .draft(let id), .final(let id): return id
        }
    }

    /// Only live preview includes open (not yet closed) sessions —
    /// answers the user's "how much have I spent so far" question.
    var includesOpenSessions: Bool {
        if case .livePreview = self { return true }
        return false
    }

    static let livePreviewRunId = "preview"
    static let draftPreviewRunId = "draft-preview"
}
