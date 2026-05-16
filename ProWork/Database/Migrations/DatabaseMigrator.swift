//
//  DatabaseMigrator.swift
//  ProWork
//
//  Created by Pronomi.
//

import Foundation
import os

enum DatabaseMigrator {
    static func migrate(_ database: AppDatabase) throws {
        try createSchemaMigrationsTable(database)

        let appliedMigrationIds = try fetchAppliedMigrationIds(database)

        for migration in allMigrations.sorted(by: { $0.id < $1.id }) {
            guard !appliedMigrationIds.contains(migration.id) else {
                continue
            }

            ProWorkLog.database.info("Running migration \(migration.id, privacy: .public): \(migration.name, privacy: .public)")

            // Her migration kendi atomic transaction'unda çalışır; herhangi
            // bir adımda hata olursa schema yarı kurulu kalmaz. Migration'ların
            // kendi içinde BEGIN/COMMIT yönetmesi gerekmez (nested transaction
            // SQLite tarafından desteklenmez); orkestratör tek otoritedir.
            try database.execute("BEGIN TRANSACTION;")
            do {
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
            Migration002BillingDocumentNumber()
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
