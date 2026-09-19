//  WorkFolderRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

enum WorkFolderRepositoryError: Error, LocalizedError, Equatable {
    case folderNotFound
    case folderNotEmpty
    case folderHasUnbilledWork

    var errorDescription: String? {
        switch self {
        case .folderNotFound:
            return ProWorkLocalizer.shared.string(
                "workFolders.error.notFound",
                defaultValue: "Klasör bulunamadı."
            )
        case .folderNotEmpty:
            return ProWorkLocalizer.shared.string(
                "workFolders.error.notEmpty",
                defaultValue: "Alt klasör veya çalışma içeren bir klasör silinemez."
            )
        case .folderHasUnbilledWork:
            return ProWorkLocalizer.shared.string(
                "workFolders.error.unbilledWork",
                defaultValue: "Faturalandırılmamış çalışma içeren bir klasör arşivlenemez."
            )
        }
    }
}

final class WorkFolderRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(
        organizationId: String = BuiltInOrganizationId.default,
        includeArchived: Bool = false
    ) throws -> [WorkFolder] {
        let sql = """
        SELECT
            id, projectId, parentFolderId, name, sortOrder, archivedAt,
            \(RecordMetadataSQL.columns)
        FROM work_folders
        WHERE organizationId = ?
          AND deletedAt IS NULL
          AND (? = 1 OR archivedAt IS NULL)
        ORDER BY sortOrder ASC, name COLLATE NOCASE ASC;
        """

        return try database.query(
            sql,
            map: { try Self.makeFolder(from: $0) },
            bind: {
                $0.bindText(organizationId, at: 1)
                $0.bindInt(includeArchived ? 1 : 0, at: 2)
            }
        )
    }

    func fetch(id: String, includeArchived: Bool = false) throws -> WorkFolder? {
        let sql = """
        SELECT
            id, projectId, parentFolderId, name, sortOrder, archivedAt,
            \(RecordMetadataSQL.columns)
        FROM work_folders
        WHERE id = ?
          AND deletedAt IS NULL
          AND (? = 1 OR archivedAt IS NULL)
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { try Self.makeFolder(from: $0) },
            bind: {
                $0.bindText(id, at: 1)
                $0.bindInt(includeArchived ? 1 : 0, at: 2)
            }
        ).first
    }

    func insert(_ folder: WorkFolder) throws {
        let archivedAt = SQLitePersistedDate.format(folder.archivedAt)
        let sql = """
        INSERT INTO work_folders (
            id, projectId, parentFolderId, name, sortOrder, archivedAt,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(folder.id, at: 1)
            statement.bindText(folder.projectId, at: 2)
            statement.bindText(folder.parentFolderId, at: 3)
            statement.bindText(folder.name, at: 4)
            statement.bindInt(folder.sortOrder, at: 5)
            statement.bindText(archivedAt, at: 6)
            statement.bindMetadata(folder.meta, startingAt: 7)
        }
    }

    func update(_ folder: WorkFolder) throws {
        let sql = """
        UPDATE work_folders
        SET projectId = ?, parentFolderId = ?, name = ?, sortOrder = ?,
            updatedByUserId = ?, updatedAt = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id = ? AND deletedAt IS NULL;
        """

        try database.execute(sql) { statement in
            statement.bindText(folder.projectId, at: 1)
            statement.bindText(folder.parentFolderId, at: 2)
            statement.bindText(folder.name, at: 3)
            statement.bindInt(folder.sortOrder, at: 4)
            statement.bindText(folder.updatedByUserId ?? BuiltInUserId.defaultOwner, at: 5)
            statement.bindText(SQLitePersistedDate.format(Date()), at: 6)
            statement.bindText(folder.id, at: 7)
        }

        guard database.lastChangedRowCount > 0 else {
            throw WorkFolderRepositoryError.folderNotFound
        }
    }

    func softDelete(id: String, by userId: String) throws {
        try database.inWriteTransaction {
            let referenceCount = try database.query("""
            SELECT
                (SELECT COUNT(*) FROM work_folders WHERE parentFolderId = ? AND deletedAt IS NULL) +
                (SELECT COUNT(*) FROM todos WHERE folderId = ? AND deletedAt IS NULL);
            """, map: { $0.int(at: 0) }, bind: { statement in
                statement.bindText(id, at: 1)
                statement.bindText(id, at: 2)
            }).first ?? 0

            guard referenceCount == 0 else {
                throw WorkFolderRepositoryError.folderNotEmpty
            }

            let now = SQLitePersistedDate.format(Date())
            try database.execute("""
            UPDATE work_folders
            SET deletedAt = ?, updatedAt = ?, updatedByUserId = ?,
                rowVersion = rowVersion + 1, syncStatus = 'local'
            WHERE id = ? AND deletedAt IS NULL;
            """) { statement in
                statement.bindText(now, at: 1)
                statement.bindText(now, at: 2)
                statement.bindText(userId, at: 3)
                statement.bindText(id, at: 4)
            }

            guard database.lastChangedRowCount > 0 else {
                throw WorkFolderRepositoryError.folderNotFound
            }
        }
    }

    func archive(id: String, by userId: String) throws {
        try database.inWriteTransaction {
            let exists = try database.query("""
            SELECT COUNT(*)
            FROM work_folders
            WHERE id = ? AND deletedAt IS NULL AND archivedAt IS NULL;
            """, map: { $0.int(at: 0) }, bind: { $0.bindText(id, at: 1) }).first ?? 0
            guard exists > 0 else {
                throw WorkFolderRepositoryError.folderNotFound
            }

            guard try !hasUnbilledWork(inSubtree: id) else {
                throw WorkFolderRepositoryError.folderHasUnbilledWork
            }

            try setArchivedAt(
                SQLitePersistedDate.format(Date()),
                forSubtree: id,
                by: userId
            )
        }
    }

    func restore(id: String, by userId: String) throws {
        try database.inWriteTransaction {
            let exists = try database.query("""
            SELECT COUNT(*)
            FROM work_folders
            WHERE id = ? AND deletedAt IS NULL AND archivedAt IS NOT NULL;
            """, map: { $0.int(at: 0) }, bind: { $0.bindText(id, at: 1) }).first ?? 0
            guard exists > 0 else {
                throw WorkFolderRepositoryError.folderNotFound
            }

            try restoreSubtreeAndAncestors(id, by: userId)
        }
    }

    private func hasUnbilledWork(inSubtree folderId: String) throws -> Bool {
        let sql = """
        WITH RECURSIVE folder_tree(id) AS (
            SELECT id FROM work_folders WHERE id = ? AND deletedAt IS NULL
            UNION ALL
            SELECT child.id
            FROM work_folders child
            INNER JOIN folder_tree parent ON child.parentFolderId = parent.id
            WHERE child.deletedAt IS NULL
        ),
        pending_sources AS (
            SELECT session.id
            FROM todo_time_sessions session
            INNER JOIN todos todo ON todo.id = session.todoId
            WHERE todo.folderId IN (SELECT id FROM folder_tree)
              AND todo.deletedAt IS NULL
              AND todo.isBillable = 1
              AND session.deletedAt IS NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM billing_report_lines line
                  INNER JOIN billing_report_runs run ON run.id = line.runId
                  WHERE line.deletedAt IS NULL
                    AND run.deletedAt IS NULL
                    AND run.status != 'cancelled'
                    AND (line.sessionId = session.id
                         OR (line.sourceKind = 'timeSession' AND line.sourceId = session.id))
              )
            UNION ALL
            SELECT billing_override.id
            FROM todo_billing_overrides billing_override
            INNER JOIN todos todo ON todo.id = billing_override.todoId
            WHERE todo.folderId IN (SELECT id FROM folder_tree)
              AND todo.deletedAt IS NULL
              AND todo.isBillable = 1
              AND billing_override.deletedAt IS NULL
              AND billing_override.overrideType IN ('projectedFee', 'fixedFee')
              AND NOT EXISTS (
                  SELECT 1
                  FROM billing_report_lines line
                  INNER JOIN billing_report_runs run ON run.id = line.runId
                  WHERE line.deletedAt IS NULL
                    AND run.deletedAt IS NULL
                    AND run.status != 'cancelled'
                    AND line.sourceKind = billing_override.overrideType
                    AND line.sourceId = billing_override.id
              )
        )
        SELECT EXISTS(SELECT 1 FROM pending_sources LIMIT 1);
        """
        return try database.query(
            sql,
            map: { $0.int(at: 0) == 1 },
            bind: { $0.bindText(folderId, at: 1) }
        ).first ?? false
    }

    private func setArchivedAt(_ archivedAt: String?, forSubtree folderId: String, by userId: String) throws {
        let now = SQLitePersistedDate.format(Date())
        try database.execute("""
        WITH RECURSIVE folder_tree(id) AS (
            SELECT id FROM work_folders WHERE id = ? AND deletedAt IS NULL
            UNION ALL
            SELECT child.id
            FROM work_folders child
            INNER JOIN folder_tree parent ON child.parentFolderId = parent.id
            WHERE child.deletedAt IS NULL
        )
        UPDATE work_folders
        SET archivedAt = ?, updatedAt = ?, updatedByUserId = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id IN (SELECT id FROM folder_tree);
        """) { statement in
            statement.bindText(folderId, at: 1)
            statement.bindText(archivedAt, at: 2)
            statement.bindText(now, at: 3)
            statement.bindText(userId, at: 4)
        }
    }

    private func restoreSubtreeAndAncestors(_ folderId: String, by userId: String) throws {
        let now = SQLitePersistedDate.format(Date())
        try database.execute("""
        WITH RECURSIVE
        folder_tree(id) AS (
            SELECT id FROM work_folders WHERE id = ? AND deletedAt IS NULL
            UNION ALL
            SELECT child.id
            FROM work_folders child
            INNER JOIN folder_tree parent ON child.parentFolderId = parent.id
            WHERE child.deletedAt IS NULL
        ),
        ancestor_tree(id, parentFolderId) AS (
            SELECT id, parentFolderId
            FROM work_folders
            WHERE id = ? AND deletedAt IS NULL
            UNION ALL
            SELECT parent.id, parent.parentFolderId
            FROM work_folders parent
            INNER JOIN ancestor_tree child ON parent.id = child.parentFolderId
            WHERE parent.deletedAt IS NULL
        ),
        restored_folders(id) AS (
            SELECT id FROM folder_tree
            UNION
            SELECT id FROM ancestor_tree
        )
        UPDATE work_folders
        SET archivedAt = NULL, updatedAt = ?, updatedByUserId = ?,
            rowVersion = rowVersion + 1, syncStatus = 'local'
        WHERE id IN (SELECT id FROM restored_folders);
        """) { statement in
            statement.bindText(folderId, at: 1)
            statement.bindText(folderId, at: 2)
            statement.bindText(now, at: 3)
            statement.bindText(userId, at: 4)
        }
    }

    private static func makeFolder(from statement: SQLiteStatement) throws -> WorkFolder {
        WorkFolder(
            id: statement.text(at: 0) ?? UUID().uuidString,
            projectId: statement.text(at: 1),
            parentFolderId: statement.text(at: 2),
            name: statement.text(at: 3) ?? "",
            sortOrder: statement.int(at: 4),
            archivedAt: SQLitePersistedDate.parse(statement.text(at: 5)),
            meta: try statement.readMetadata(startingAt: 6)
        )
    }
}
