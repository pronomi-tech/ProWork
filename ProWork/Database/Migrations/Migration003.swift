//  Migration003.swift
//  ProWork
//  Created by Pronomi.

import Foundation

/// Applies the billing-model and work-folder schema changes introduced after
/// Migration002 while preserving existing rows and foreign-key identities.
struct Migration003: Migration {
    let id = 3
    let name = "billing_model_and_work_folders"
    let requiresForeignKeysDisabled = true

    func up(_ database: AppDatabase) throws {
        try createReplacementOrganizations(database)
        try createReplacementProjects(database)
        try copyRows(database)

        try database.execute("DROP TABLE projects;")
        try database.execute("DROP TABLE organizations;")
        try database.execute("ALTER TABLE organizations_v3 RENAME TO organizations;")
        try database.execute("ALTER TABLE projects_v3 RENAME TO projects;")

        try recreateProjectIndexes(database)
        try recreateProjectSoftDeleteTrigger(database)
        try addWorkSessionTimeTypeOverride(database)
        try addBillingSecondPrecision(database)
        try createWorkFoldersTable(database)
        try addFolderReferenceToTodos(database)
        try createScopeAndCycleTriggers(database)
        try createProjectWorkFolderSoftDeleteTrigger(database)
    }

    private func createReplacementOrganizations(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE organizations_v3 (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            slug TEXT UNIQUE,
            masterCurrency TEXT NOT NULL DEFAULT 'TRY',
            billingWindowMode TEXT NOT NULL DEFAULT 'timeline'
                CHECK(billingWindowMode IN ('timeline','session','report')),
            isActive INTEGER NOT NULL DEFAULT 1,
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT
        );
        """)
    }

    private func createReplacementProjects(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE projects_v3 (
            id TEXT PRIMARY KEY NOT NULL,
            customerId TEXT NOT NULL,
            name TEXT NOT NULL,
            code TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            defaultServiceType TEXT,
            defaultMinBillingMinutes INTEGER,
            billingWindowMode TEXT
                CHECK(billingWindowMode IN ('timeline','session','report')),
            vatRateId TEXT,
            notes TEXT,
            organizationId TEXT NOT NULL DEFAULT 'default_organization',
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            FOREIGN KEY (customerId) REFERENCES customers(id),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE,
            FOREIGN KEY (vatRateId) REFERENCES vat_rates(id) ON DELETE SET NULL
        );
        """)
    }

    private func copyRows(_ database: AppDatabase) throws {
        try database.execute("""
        INSERT INTO organizations_v3
        SELECT id, name, slug, masterCurrency, billingWindowMode, isActive,
               createdByUserId, updatedByUserId, createdAt, updatedAt, deletedAt,
               rowVersion, syncStatus, lastSyncedAt, originDeviceId
        FROM organizations;
        """)

        try database.execute("""
        INSERT INTO projects_v3
        SELECT id, customerId, name, code, status, defaultServiceType,
               defaultMinBillingMinutes, billingWindowMode, vatRateId, notes,
               organizationId, createdByUserId, updatedByUserId, createdAt,
               updatedAt, deletedAt, rowVersion, syncStatus, lastSyncedAt,
               originDeviceId
        FROM projects;
        """)
    }

    private func recreateProjectIndexes(_ database: AppDatabase) throws {
        try database.execute("CREATE INDEX idx_projects_customerId ON projects(customerId);")
        try database.execute("CREATE INDEX idx_projects_name ON projects(name COLLATE NOCASE);")
        try database.execute("CREATE INDEX idx_projects_organizationId ON projects(organizationId);")
        try database.execute("CREATE INDEX idx_projects_deletedAt ON projects(deletedAt);")
        try database.execute("CREATE INDEX idx_projects_vatRateId ON projects(vatRateId);")
    }

    private func recreateProjectSoftDeleteTrigger(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TRIGGER trg_projects_softdelete_cascade_todos
        AFTER UPDATE OF deletedAt ON projects
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE todos
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE projectId = NEW.id AND deletedAt IS NULL;
        END;
        """)
    }

    private func addWorkSessionTimeTypeOverride(_ database: AppDatabase) throws {
        try database.execute("""
        ALTER TABLE todo_time_sessions
        ADD COLUMN billingTimeTypeOverride TEXT
            CHECK(billingTimeTypeOverride IS NULL OR billingTimeTypeOverride IN ('regular','afterHours','weekend','holiday'));
        """)

        try database.execute("""
        ALTER TABLE todo_time_sessions
        ADD COLUMN billingTimeTypeOverrideReason TEXT
            CHECK(billingTimeTypeOverride IS NOT NULL OR billingTimeTypeOverrideReason IS NULL);
        """)
    }

    private func addBillingSecondPrecision(_ database: AppDatabase) throws {
        try database.execute("""
        ALTER TABLE billing_report_lines
        ADD COLUMN billableSeconds INTEGER NOT NULL DEFAULT 0
            CHECK(billableSeconds >= 0);
        """)

        // Historical statement lines only retained whole billable minutes.
        // Preserve their former monetary meaning exactly during backfill.
        try database.execute("""
        UPDATE billing_report_lines
        SET billableSeconds = billableMinutes * 60;
        """)
    }

    private func createWorkFoldersTable(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TABLE work_folders (
            id TEXT PRIMARY KEY NOT NULL,
            projectId TEXT,
            parentFolderId TEXT,
            name TEXT NOT NULL CHECK(length(trim(name)) > 0),
            sortOrder INTEGER NOT NULL DEFAULT 0,
            organizationId TEXT NOT NULL DEFAULT 'default_organization',
            createdByUserId TEXT,
            updatedByUserId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            rowVersion INTEGER NOT NULL DEFAULT 0,
            syncStatus TEXT NOT NULL DEFAULT 'local',
            lastSyncedAt TEXT,
            originDeviceId TEXT,
            CHECK(parentFolderId IS NULL OR parentFolderId <> id),
            FOREIGN KEY (projectId) REFERENCES projects(id),
            FOREIGN KEY (parentFolderId) REFERENCES work_folders(id),
            FOREIGN KEY (organizationId) REFERENCES organizations(id) ON DELETE CASCADE
        );
        """)

        try database.execute("CREATE INDEX idx_work_folders_projectId ON work_folders(projectId);")
        try database.execute("CREATE INDEX idx_work_folders_parentFolderId ON work_folders(parentFolderId);")
        try database.execute("CREATE INDEX idx_work_folders_organizationId ON work_folders(organizationId);")
        try database.execute("CREATE INDEX idx_work_folders_deletedAt ON work_folders(deletedAt);")
        try database.execute("""
        CREATE UNIQUE INDEX idx_work_folders_unique_active_sibling_name
        ON work_folders(
            organizationId,
            COALESCE(projectId, ''),
            COALESCE(parentFolderId, ''),
            name COLLATE NOCASE
        )
        WHERE deletedAt IS NULL;
        """)
    }

    private func addFolderReferenceToTodos(_ database: AppDatabase) throws {
        try database.execute("""
        ALTER TABLE todos
        ADD COLUMN folderId TEXT REFERENCES work_folders(id);
        """)
        try database.execute("CREATE INDEX idx_todos_folderId ON todos(folderId);")
    }

    private func createScopeAndCycleTriggers(_ database: AppDatabase) throws {
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
                          AND folder.organizationId = NEW.organizationId
                          AND folder.projectId IS NEW.projectId
                    )
                    THEN RAISE(ABORT, 'Todo folder must be active and in the same project scope')
                END;
            END;
            """)
        }
    }

    private func createProjectWorkFolderSoftDeleteTrigger(_ database: AppDatabase) throws {
        try database.execute("""
        CREATE TRIGGER trg_projects_softdelete_cascade_work_folders
        AFTER UPDATE OF deletedAt ON projects
        WHEN OLD.deletedAt IS NULL AND NEW.deletedAt IS NOT NULL
        BEGIN
            UPDATE work_folders
            SET deletedAt = NEW.deletedAt,
                updatedAt = NEW.updatedAt,
                updatedByUserId = NEW.updatedByUserId,
                rowVersion = rowVersion + 1,
                syncStatus = 'local'
            WHERE projectId = NEW.id AND deletedAt IS NULL;
        END;
        """)
    }
}
