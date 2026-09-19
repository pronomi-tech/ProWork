//  Migration004.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Adds session-independent billing sources and work-folder archiving while
/// preserving existing tracked-time and fixed-fee data.
struct Migration004: Migration {
    let id = 4
    let name = "projected_fees_billing_sources_and_folder_archiving"
    let requiresForeignKeysDisabled = true

    func up(_ database: AppDatabase) throws {
        try Self.repairLegacyDefaultOrganizationReferences(database)

        try database.execute("DROP TRIGGER IF EXISTS trg_todos_softdelete_cascade_overrides;")
        try createReplacementOverrides(database)
        try copyOverrides(database)
        try database.execute("DROP TABLE todo_billing_overrides;")
        try database.execute("ALTER TABLE todo_billing_overrides_v4 RENAME TO todo_billing_overrides;")
        try recreateOverrideIndexes(database)
        try recreateOverrideSoftDeleteTrigger(database)

        try database.execute("ALTER TABLE billing_report_lines ADD COLUMN sourceKind TEXT;")
        try database.execute("ALTER TABLE billing_report_lines ADD COLUMN sourceId TEXT;")
        try database.execute("""
        UPDATE billing_report_lines
        SET sourceKind = 'timeSession', sourceId = sessionId
        WHERE sessionId IS NOT NULL;
        """)
        try database.execute("""
        CREATE INDEX idx_billing_lines_source
        ON billing_report_lines(organizationId, sourceKind, sourceId)
        WHERE sourceKind IS NOT NULL AND sourceId IS NOT NULL;
        """)

        try database.execute("ALTER TABLE work_folders ADD COLUMN archivedAt TEXT;")
        try database.execute("CREATE INDEX idx_work_folders_archivedAt ON work_folders(archivedAt);")
        try recreateActiveFolderScopeTriggers(database)
    }

    static func repairLegacyDefaultOrganizationReferences(_ database: AppDatabase) throws {
        // Early builds used `default_organization` for generated global
        // holidays, while the seeded organization has always been
        // `org_default`. Narrow the repair to that retired identifier and
        // only when it does not represent a real organization.
        try database.execute("""
        UPDATE holidays
        SET organizationId = ?
        WHERE organizationId = 'default_organization'
          AND scope = 'global'
          AND NOT EXISTS (
              SELECT 1 FROM organizations WHERE id = 'default_organization'
          )
          AND EXISTS (
              SELECT 1 FROM organizations WHERE id = ?
          );
        """) { statement in
            statement.bindText(BuiltInOrganizationId.default, at: 1)
            statement.bindText(BuiltInOrganizationId.default, at: 2)
        }
    }

    private func createReplacementOverrides(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE todo_billing_overrides_v4 (
            id TEXT PRIMARY KEY NOT NULL,
            organizationId TEXT NOT NULL,
            todoId TEXT NOT NULL UNIQUE,
            overrideType TEXT NOT NULL
                CHECK(overrideType IN ('unitPrice','projectedFee','fixedFee')),
            unitPriceMinor INTEGER,
            projectedBillableSeconds INTEGER,
            fixedFeeMinor INTEGER,
            currency TEXT NOT NULL,
            note TEXT,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            CHECK (
                (overrideType = 'unitPrice'
                    AND unitPriceMinor IS NOT NULL
                    AND projectedBillableSeconds IS NULL
                    AND fixedFeeMinor IS NULL)
             OR (overrideType = 'projectedFee'
                    AND unitPriceMinor IS NOT NULL
                    AND projectedBillableSeconds IS NOT NULL
                    AND projectedBillableSeconds > 0
                    AND fixedFeeMinor IS NULL)
             OR (overrideType = 'fixedFee'
                    AND unitPriceMinor IS NULL
                    AND projectedBillableSeconds IS NULL
                    AND fixedFeeMinor IS NOT NULL)
            ),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (todoId) REFERENCES todos(id) ON DELETE CASCADE
        );
        """)
    }

    private func copyOverrides(_ database: AppDatabase) throws {
        try database.execute("""
        INSERT INTO todo_billing_overrides_v4 (
            id, organizationId, todoId, overrideType,
            unitPriceMinor, projectedBillableSeconds, fixedFeeMinor, currency, note,
            createdByUserId, updatedByUserId, createdAt, updatedAt, deletedAt,
            rowVersion, syncStatus, lastSyncedAt, originDeviceId
        )
        SELECT
            id, organizationId, todoId, overrideType,
            unitPriceMinor, NULL, fixedFeeMinor, currency, note,
            createdByUserId, updatedByUserId, createdAt, updatedAt, deletedAt,
            rowVersion, syncStatus, lastSyncedAt, originDeviceId
        FROM todo_billing_overrides;
        """)
    }

    private func recreateOverrideIndexes(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE INDEX idx_todo_billing_overrides_org_type
        ON todo_billing_overrides(organizationId, overrideType)
        WHERE deletedAt IS NULL;
        """)
    }

    private func recreateOverrideSoftDeleteTrigger(_ database: AppDatabase) throws {
        try database.execute("DROP TRIGGER IF EXISTS trg_todos_softdelete_cascade_overrides;")
        try database.execute("""
        CREATE TRIGGER trg_todos_softdelete_cascade_overrides
        AFTER UPDATE OF deletedAt ON todos
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE todo_billing_overrides
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE todoId = NEW.id AND deletedAt IS NULL;
        END;
        """)
    }

    private func recreateActiveFolderScopeTriggers(_ database: AppDatabase) throws {
        try database.execute("DROP TRIGGER IF EXISTS trg_work_folders_validate_insert;")
        try database.execute("DROP TRIGGER IF EXISTS trg_work_folders_validate_update_scope;")
        try database.execute("DROP TRIGGER IF EXISTS trg_todos_validate_folder_insert;")
        try database.execute("DROP TRIGGER IF EXISTS trg_todos_validate_folder_update_folder;")

        for operation in [
            (name: "insert", clause: "INSERT"),
            (name: "update_scope", clause: "UPDATE OF projectId, parentFolderId, organizationId")
        ] {
            try database.execute("""
            CREATE TRIGGER trg_work_folders_validate_\(operation.name)
            BEFORE \(operation.clause) ON work_folders
            BEGIN
                SELECT CASE
                    WHEN NEW.projectId IS NOT NULL AND NOT EXISTS (
                        SELECT 1
                        FROM projects project
                        WHERE project.id = NEW.projectId
                          AND project.deletedAt IS NULL
                          AND project.organizationId = NEW.organizationId
                    )
                    THEN RAISE(ABORT, 'Folder project must be active and in the same organization')
                END;

                SELECT CASE
                    WHEN NEW.parentFolderId IS NOT NULL AND NOT EXISTS (
                        SELECT 1
                        FROM work_folders parent
                        WHERE parent.id = NEW.parentFolderId
                          AND parent.deletedAt IS NULL
                          AND parent.archivedAt IS NULL
                          AND parent.organizationId = NEW.organizationId
                          AND parent.projectId IS NEW.projectId
                    )
                    THEN RAISE(ABORT, 'Folder parent must be active and in the same scope')
                END;

                SELECT CASE
                    WHEN NEW.parentFolderId IS NOT NULL AND EXISTS (
                        WITH RECURSIVE ancestors(id, parentFolderId) AS (
                            SELECT id, parentFolderId
                            FROM work_folders
                            WHERE id = NEW.parentFolderId
                            UNION ALL
                            SELECT folder.id, folder.parentFolderId
                            FROM work_folders folder
                            INNER JOIN ancestors ON folder.id = ancestors.parentFolderId
                        )
                        SELECT 1 FROM ancestors WHERE id = NEW.id
                    )
                    THEN RAISE(ABORT, 'Folder hierarchy cannot contain a cycle')
                END;
            END;
            """)
        }

        for operation in [
            (name: "insert", clause: "INSERT"),
            (name: "update_folder", clause: "UPDATE OF folderId, projectId, organizationId")
        ] {
            try database.execute("""
            CREATE TRIGGER trg_todos_validate_folder_\(operation.name)
            BEFORE \(operation.clause) ON todos
            WHEN NEW.folderId IS NOT NULL
            BEGIN
                SELECT CASE
                    WHEN NOT EXISTS (
                        SELECT 1
                        FROM work_folders folder
                        WHERE folder.id = NEW.folderId
                          AND folder.deletedAt IS NULL
                          AND folder.archivedAt IS NULL
                          AND folder.organizationId = NEW.organizationId
                          AND folder.projectId IS NEW.projectId
                    )
                    THEN RAISE(ABORT, 'Todo folder must be active and in the same project scope')
                END;
            END;
            """)
        }
    }
}
