//  WorkFolderRepository.swift
//  ProWork
//  Created by Pronomi.

import Foundation
import SQLite3

enum WorkFolderRepositoryError: Error, LocalizedError, Equatable {
    case folderNotFound
    case folderNotEmpty

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
        }
    }
}

final class WorkFolderRepository {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func fetchAll(organizationId: String = BuiltInOrganizationId.default) throws -> [WorkFolder] {
        let sql = """
        SELECT
            id, projectId, parentFolderId, name, sortOrder,
            \(RecordMetadataSQL.columns)
        FROM work_folders
        WHERE organizationId = ? AND deletedAt IS NULL
        ORDER BY sortOrder ASC, name COLLATE NOCASE ASC;
        """

        return try database.query(
            sql,
            map: { try Self.makeFolder(from: $0) },
            bind: { $0.bindText(organizationId, at: 1) }
        )
    }

    func fetch(id: String) throws -> WorkFolder? {
        let sql = """
        SELECT
            id, projectId, parentFolderId, name, sortOrder,
            \(RecordMetadataSQL.columns)
        FROM work_folders
        WHERE id = ? AND deletedAt IS NULL
        LIMIT 1;
        """

        return try database.query(
            sql,
            map: { try Self.makeFolder(from: $0) },
            bind: { $0.bindText(id, at: 1) }
        ).first
    }

    func insert(_ folder: WorkFolder) throws {
        let sql = """
        INSERT INTO work_folders (
            id, projectId, parentFolderId, name, sortOrder,
            \(RecordMetadataSQL.columns)
        )
        VALUES (?, ?, ?, ?, ?, \(RecordMetadataSQL.placeholders));
        """

        try database.execute(sql) { statement in
            statement.bindText(folder.id, at: 1)
            statement.bindText(folder.projectId, at: 2)
            statement.bindText(folder.parentFolderId, at: 3)
            statement.bindText(folder.name, at: 4)
            statement.bindInt(folder.sortOrder, at: 5)
            statement.bindMetadata(folder.meta, startingAt: 6)
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

    private static func makeFolder(from statement: SQLiteStatement) throws -> WorkFolder {
        WorkFolder(
            id: statement.text(at: 0) ?? UUID().uuidString,
            projectId: statement.text(at: 1),
            parentFolderId: statement.text(at: 2),
            name: statement.text(at: 3) ?? "",
            sortOrder: statement.int(at: 4),
            meta: try statement.readMetadata(startingAt: 5)
        )
    }
}
