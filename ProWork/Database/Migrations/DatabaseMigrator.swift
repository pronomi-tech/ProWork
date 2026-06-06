//  DatabaseMigrator.swift
//  ProWork
//  Created by Pronomi.
//  Forward-only migrator. Each migration is applied in its own atomic
//  transaction; a row is recorded in the `schema_migrations` table.
//
//  - Rollback: `down()` is deliberately absent. If a buggy migration
//    becomes stuck in production, the recovery path is **manual
//    restore**: restoring the user's data file from an iCloud Drive /
//    Time Machine snapshot. The forward-only flow was chosen to
//    minimize the risk of half-applied schemas.
//  - FK policy consistency: `projects.customerId` and
//    `todos.customerId` were defined in Migration001 without an
//    explicit `ON DELETE` policy. The compensating behavior lives in
//    Migration002's `trg_customers_block_delete_if_referenced` trigger:
//    hard-delete is blocked with `RAISE(ABORT)` when active references
//    exist, while soft-delete flows through the cascade triggers
//    installed in the same migration.

import Foundation
import os

enum DatabaseMigrator {
    /// Accidentally reusing an existing id when adding a new migration
    /// causes the orchestrator to silently treat the second migration
    /// as "already applied" and skip it. To detect this early, a
    /// duplicate id is thrown as a fatal error.
    enum MigratorError: Error, LocalizedError {
        case duplicateMigrationId(Int, names: [String])
        var errorDescription: String? {
            switch self {
            case .duplicateMigrationId(let id, let names):
                return "Duplicate migration id \(id) declared by: \(names.joined(separator: ", "))."
            }
        }
    }

    static func migrate(_ database: AppDatabase) throws {
        try createSchemaMigrationsTable(database)

        let migrationsById = Dictionary(grouping: allMigrations, by: { $0.id })
        if let duplicate = migrationsById.first(where: { $0.value.count > 1 }) {
            throw MigratorError.duplicateMigrationId(
                duplicate.key,
                names: duplicate.value.map(\.name)
            )
        }

        let appliedMigrationIds = try fetchAppliedMigrationIds(database)

        for migration in allMigrations.sorted(by: { $0.id < $1.id }) {
            guard !appliedMigrationIds.contains(migration.id) else {
                continue
            }

            ProWorkLog.database.info("Running migration \(migration.id, privacy: .public): \(migration.name, privacy: .public)")

            // Each migration runs in its own atomic transaction; if any
            // step fails the schema is not left half-built. Migrations
            // do not need to manage BEGIN/COMMIT themselves (nested
            // transactions are not supported by SQLite); the
            // orchestrator is the sole authority.
            // `PRAGMA defer_foreign_keys = ON` defers FK checks for the
            // duration of the transaction. Even if a migration seeds
            // the child table before the parent, FK violations are
            // caught in the bulk check just before COMMIT — removing
            // sensitivity to insertion order.
            // The PRAGMA resets automatically at the end of each
            // transaction.
            try database.execute("BEGIN TRANSACTION;")
            do {
                try database.execute("PRAGMA defer_foreign_keys = ON;")
                try migration.up(database)
                try insertAppliedMigration(database, migration: migration)
                try database.execute("COMMIT;")
            } catch {
                try? database.execute("ROLLBACK;")
                throw error
            }

            ProWorkLog.database.info("Migration \(migration.id, privacy: .public) completed")
        }
    }

    private static var allMigrations: [Migration] {
        [
            Migration001InitialSchema(),
            Migration002Consolidated()
        ]
    }

    private static func createSchemaMigrationsTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            id INTEGER PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            appliedAt TEXT NOT NULL
        );
        """)
    }

    private static func fetchAppliedMigrationIds(_ database: AppDatabase) throws -> Set<Int> {
        let rows = try database.query("""
        SELECT id
        FROM schema_migrations;
        """) { statement in
            statement.int(at: 0)
        }

        return Set(rows)
    }

    private static func insertAppliedMigration(
        _ database: AppDatabase,
        migration: Migration
    ) throws {
        try database.execute("""
        INSERT INTO schema_migrations (
            id,
            name,
            appliedAt
        )
        VALUES (?, ?, ?);
        """) { statement in
            statement.bindInt(migration.id, at: 1)
            statement.bindText(migration.name, at: 2)
            statement.bindText(DateFormatter.proWorkSQLite.string(from: Date()), at: 3)
        }
    }
}
