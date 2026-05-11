//
//  WorkSessionListItem.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation

struct WorkSessionListItem: Identifiable, Hashable {
    let id: String

    var todoId: String
    var todoTitle: String

    var customerName: String?
    var projectName: String?

    var statusId: String
    var statusName: String
    var statusColor: String?
    var statusStartsTimer: Bool
    var statusStopsTimer: Bool
    var statusMarksCompleted: Bool
    var statusMarksCancelled: Bool

    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int?
    var isManual: Bool
    var note: String?

    var createdAt: Date
    var updatedAt: Date
}
