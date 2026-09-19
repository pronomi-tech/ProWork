//  Migration005.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Persists whether a todo is performed by an AI agent so idle automation can
/// exempt it without copying the flag into report or work-session records.
struct Migration005: Migration {
    let id = 5
    let name = "todo_ai_agent_idle_exemption"

    func up(_ database: AppDatabase) throws {
        try database.execute("""
        ALTER TABLE todos
        ADD COLUMN isAIAgentTask INTEGER NOT NULL DEFAULT 0
            CHECK(isAIAgentTask IN (0, 1));
        """)
    }
}
