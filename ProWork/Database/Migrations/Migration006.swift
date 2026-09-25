//  Migration006.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Snapshots per-session billing choices so later project, customer, or
/// organization default changes cannot reinterpret completed work.
struct Migration006: Migration {
    let id = 6
    let name = "work_session_billing_controls"

    func up(_ database: AppDatabase) throws {
        try database.execute("""
        ALTER TABLE todo_time_sessions
        ADD COLUMN serviceType TEXT NOT NULL DEFAULT 'remote'
            CHECK(serviceType IN ('remote', 'onsite'));
        """)

        try database.execute("""
        UPDATE todo_time_sessions
        SET serviceType = COALESCE(
            (
                SELECT CASE
                    WHEN p.defaultServiceType IN ('remote', 'onsite') THEN p.defaultServiceType
                    ELSE NULL
                END
                FROM todos t
                LEFT JOIN projects p ON p.id = t.projectId AND p.deletedAt IS NULL
                WHERE t.id = todo_time_sessions.todoId
            ),
            (
                SELECT CASE
                    WHEN c.defaultServiceType IN ('remote', 'onsite') THEN c.defaultServiceType
                    ELSE NULL
                END
                FROM todos t
                LEFT JOIN projects p ON p.id = t.projectId AND p.deletedAt IS NULL
                LEFT JOIN customers c ON c.id = COALESCE(t.customerId, p.customerId) AND c.deletedAt IS NULL
                WHERE t.id = todo_time_sessions.todoId
            ),
            'remote'
        );
        """)

        try database.execute("""
        ALTER TABLE todo_time_sessions
        ADD COLUMN billingWindowModeOverride TEXT
            CHECK(billingWindowModeOverride IS NULL OR billingWindowModeOverride = 'session');
        """)
    }
}
