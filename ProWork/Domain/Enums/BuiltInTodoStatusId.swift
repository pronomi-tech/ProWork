//  BuiltInTodoStatusId.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// `nonisolated static let` matches `BuiltInOrganizationId` /
/// `BuiltInUserId` so the constants are reachable from any actor
/// context (Swift 6 default isolation enforcement otherwise routes
/// them through MainActor and breaks background repository reads).
enum BuiltInTodoStatusId {
    nonisolated static let waiting = "status_waiting"
    nonisolated static let inProgress = "status_in_progress"
    nonisolated static let done = "status_done"
    nonisolated static let cancelled = "status_cancelled"
}
