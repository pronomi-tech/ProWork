//  TodoListItem.swift
//  ProWork
//  Created by Pronomi.

import Foundation

struct TodoListItem: Identifiable, Hashable {
    let id: String

    var customerId: String?
    var customerName: String?

    var projectId: String?
    var projectName: String?

    var folderId: String? = nil
    var folderName: String? = nil

    var categoryId: String
    var categoryName: String
    var categoryColor: String?
    var categoryIsBillable: Bool

    var statusId: String
    var statusName: String
    var statusColor: String?
    var statusStartsTimer: Bool
    var statusStopsTimer: Bool
    var statusMarksOpen: Bool
    var statusMarksCompleted: Bool
    var statusMarksCancelled: Bool

    var title: String
    var description: String?

    var priority: String

    var plannedDate: Date?
    var dueDate: Date?
    var estimatedMinutes: Int?

    var totalTrackedSeconds: Int
    var activeSessionStartedAt: Date?

    var isBillable: Bool

    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
}
