//  WorkFolderHierarchy.swift
//  ProWork
//  Created by Pronomi.

import Foundation

struct WorkFolderTreeItem: Identifiable, Hashable {
    let folder: WorkFolder
    let depth: Int
    let path: String

    var id: String { folder.id }
}

struct WorkFolderTreeNode: Identifiable, Hashable {
    let folder: WorkFolder
    let children: [WorkFolderTreeNode]?

    var id: String { folder.id }
}

enum WorkFolderHierarchy {
    static func flattened(
        _ folders: [WorkFolder],
        projectId: String?,
        excluding excludedIds: Set<String> = []
    ) -> [WorkFolderTreeItem] {
        let scoped = folders.filter {
            $0.projectId == projectId && !excludedIds.contains($0.id)
        }
        let childrenByParent = Dictionary(grouping: scoped, by: \WorkFolder.parentFolderId)
        let roots = sorted(childrenByParent[nil] ?? [])

        var result: [WorkFolderTreeItem] = []
        var visited: Set<String> = []
        var stack = roots.reversed().map { ($0, 0, $0.name) }

        while let (folder, depth, path) = stack.popLast() {
            guard visited.insert(folder.id).inserted else { continue }
            result.append(WorkFolderTreeItem(folder: folder, depth: depth, path: path))

            let children = sorted(childrenByParent[folder.id] ?? [])
            for child in children.reversed() {
                stack.append((child, depth + 1, "\(path) / \(child.name)"))
            }
        }

        return result
    }

    static func nodes(_ folders: [WorkFolder], projectId: String?) -> [WorkFolderTreeNode] {
        let scoped = folders.filter { $0.projectId == projectId }
        let childrenByParent = Dictionary(grouping: scoped, by: \WorkFolder.parentFolderId)
        var visited: Set<String> = []

        func makeNode(_ folder: WorkFolder) -> WorkFolderTreeNode {
            guard visited.insert(folder.id).inserted else {
                return WorkFolderTreeNode(folder: folder, children: nil)
            }
            let children = sorted(childrenByParent[folder.id] ?? []).map(makeNode)
            return WorkFolderTreeNode(folder: folder, children: children.isEmpty ? nil : children)
        }

        return sorted(childrenByParent[nil] ?? []).map(makeNode)
    }

    static func descendantIds(of folderId: String, in folders: [WorkFolder]) -> Set<String> {
        let childrenByParent = Dictionary(grouping: folders, by: \WorkFolder.parentFolderId)
        var result: Set<String> = []
        var pending = [folderId]

        while let current = pending.popLast() {
            guard result.insert(current).inserted else { continue }
            pending.append(contentsOf: (childrenByParent[current] ?? []).map(\.id))
        }

        return result
    }

    private static func sorted(_ folders: [WorkFolder]) -> [WorkFolder] {
        folders.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

enum WorkLocationSelection: Hashable {
    case all
    case project(String)
    case folder(String)

    func assignment(
        projects: [ProjectListItem],
        folders: [WorkFolder]
    ) -> WorkLocationAssignment {
        switch self {
        case .all:
            return WorkLocationAssignment()
        case .project(let projectId):
            let customerId = projects.first(where: { $0.id == projectId })?.customerId
            return WorkLocationAssignment(customerId: customerId, projectId: projectId)
        case .folder(let folderId):
            guard let folder = folders.first(where: { $0.id == folderId }) else {
                return WorkLocationAssignment()
            }

            let customerId = folder.projectId.flatMap { projectId in
                projects.first(where: { $0.id == projectId })?.customerId
            }
            return WorkLocationAssignment(
                customerId: customerId,
                projectId: folder.projectId,
                folderId: folder.id
            )
        }
    }
}

struct WorkLocationAssignment: Equatable {
    var customerId: String?
    var projectId: String?
    var folderId: String?

    init(
        customerId: String? = nil,
        projectId: String? = nil,
        folderId: String? = nil
    ) {
        self.customerId = customerId
        self.projectId = projectId
        self.folderId = folderId
    }
}
