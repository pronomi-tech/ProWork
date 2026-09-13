//  WorkFolderSidebar.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct WorkFolderSidebar: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @State private var expandedProjectIds: Set<String> = []
    @State private var expandedFolderIds: Set<String> = []

    let projects: [ProjectListItem]
    let folders: [WorkFolder]
    let itemCount: (WorkLocationSelection, Bool) -> Int
    @Binding var selection: WorkLocationSelection
    @Binding var includeDescendantFolders: Bool
    let onCreateIndependentFolder: () -> Void
    let onCreateProjectFolder: (ProjectListItem) -> Void
    let onCreateChildFolder: (WorkFolder) -> Void
    let onEditFolder: (WorkFolder) -> Void
    let onDeleteFolder: (WorkFolder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(settingsStore.localized("workFolders.sidebar.title", defaultValue: "Klasörler ve Projeler"))
                    .proWorkTextStyle(.headline)
                Spacer()
                Button(action: onCreateIndependentFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help(settingsStore.localized("workFolders.action.newIndependent", defaultValue: "Yeni bağımsız klasör"))
            }
            .padding(.horizontal, 10)

            List {
                selectionRow(
                    title: settingsStore.localized("workFolders.sidebar.all", defaultValue: "Tüm Çalışmalar"),
                    systemImage: "tray.full",
                    count: itemCount(.all, false),
                    value: .all
                )

                let globalNodes = WorkFolderHierarchy.nodes(folders, projectId: nil)
                if !globalNodes.isEmpty {
                    Section(settingsStore.localized("workFolders.sidebar.independent", defaultValue: "Bağımsız Klasörler")) {
                        ForEach(visibleFolderRows(globalNodes, startingDepth: 0)) { row in
                            folderRow(row)
                        }
                    }
                }

                if !projects.isEmpty {
                    Section(settingsStore.localized("projects.title", defaultValue: "Projeler")) {
                        ForEach(projects) { project in
                            let nodes = WorkFolderHierarchy.nodes(folders, projectId: project.id)
                            projectRow(project, hasChildren: !nodes.isEmpty)

                            if expandedProjectIds.contains(project.id) {
                                ForEach(visibleFolderRows(nodes, startingDepth: 1)) { row in
                                    folderRow(row)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Toggle(
                settingsStore.localized(
                    "workFolders.sidebar.includeSubfolders",
                    defaultValue: "Alt klasörleri dahil et"
                ),
                isOn: $includeDescendantFolders
            )
            .toggleStyle(.checkbox)
            .padding(.horizontal, 10)
            .disabled(!selectionSupportsDescendants)
        }
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func projectRow(_ project: ProjectListItem, hasChildren: Bool) -> some View {
        hierarchyRowContent(
            title: project.name,
            subtitle: project.customerName,
            systemImage: "folder.fill",
            count: itemCount(.project(project.id), includeDescendantFolders),
            isSelected: selection == .project(project.id),
            depth: 0,
            hasChildren: hasChildren,
            isExpanded: expandedProjectIds.contains(project.id),
            onSelect: { selection = .project(project.id) },
            onToggleExpansion: { toggleExpansion(ofProject: project.id) }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard hasChildren else { return }
                toggleExpansion(ofProject: project.id)
            }
        )
        .contextMenu {
            Button {
                onCreateProjectFolder(project)
            } label: {
                Label(
                    settingsStore.localized("workFolders.action.newChild", defaultValue: "Alt Klasör Ekle"),
                    systemImage: "folder.badge.plus"
                )
            }
        }
    }

    private func folderRow(_ row: VisibleFolderRow) -> some View {
        let folder = row.node.folder
        return hierarchyRowContent(
            title: folder.name,
            subtitle: nil,
            systemImage: "folder",
            count: itemCount(.folder(folder.id), includeDescendantFolders),
            isSelected: selection == .folder(folder.id),
            depth: row.depth,
            hasChildren: row.hasChildren,
            isExpanded: expandedFolderIds.contains(folder.id),
            onSelect: { selection = .folder(folder.id) },
            onToggleExpansion: { toggleExpansion(ofFolder: folder.id) }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard row.hasChildren else { return }
                toggleExpansion(ofFolder: folder.id)
            }
        )
        .contextMenu {
            Button {
                onCreateChildFolder(folder)
            } label: {
                Label(
                    settingsStore.localized("workFolders.action.newChild", defaultValue: "Alt Klasör Ekle"),
                    systemImage: "folder.badge.plus"
                )
            }
            Button {
                onEditFolder(folder)
            } label: {
                Label(settingsStore.localized("common.edit", defaultValue: "Düzenle"), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                onDeleteFolder(folder)
            } label: {
                Label(settingsStore.localized("common.delete", defaultValue: "Sil"), systemImage: "trash")
            }
        }
    }

    private func selectionRow(
        title: String,
        systemImage: String,
        count: Int,
        value: WorkLocationSelection
    ) -> some View {
        Button {
            selection = value
        } label: {
            selectionRowContent(
                title: title,
                subtitle: nil,
                systemImage: systemImage,
                count: count,
                isSelected: selection == value
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionRowContent(
        title: String,
        subtitle: String?,
        systemImage: String,
        count: Int,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(count)")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func hierarchyRowContent(
        title: String,
        subtitle: String?,
        systemImage: String,
        count: Int,
        isSelected: Bool,
        depth: Int,
        hasChildren: Bool,
        isExpanded: Bool,
        onSelect: @escaping () -> Void,
        onToggleExpansion: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: onToggleExpansion) {
                if hasChildren {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                } else {
                    Color.clear
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren)
            .frame(width: 14, height: 18)

            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .proWorkTextStyle(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(count)")
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .padding(.leading, CGFloat(depth) * 24)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func visibleFolderRows(
        _ nodes: [WorkFolderTreeNode],
        startingDepth: Int
    ) -> [VisibleFolderRow] {
        var result: [VisibleFolderRow] = []
        var pending = nodes.reversed().map { ($0, startingDepth) }

        while let (node, depth) = pending.popLast() {
            result.append(VisibleFolderRow(node: node, depth: depth))
            guard expandedFolderIds.contains(node.id), let children = node.children else { continue }
            pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
        }

        return result
    }

    private func toggleExpansion(ofProject projectId: String) {
        if !expandedProjectIds.insert(projectId).inserted {
            expandedProjectIds.remove(projectId)
        }
    }

    private func toggleExpansion(ofFolder folderId: String) {
        if !expandedFolderIds.insert(folderId).inserted {
            expandedFolderIds.remove(folderId)
        }
    }

    private var selectionSupportsDescendants: Bool {
        switch selection {
        case .project, .folder:
            return true
        case .all:
            return false
        }
    }
}

private struct VisibleFolderRow: Identifiable {
    let node: WorkFolderTreeNode
    let depth: Int

    var id: String { node.id }
    var hasChildren: Bool { node.children?.isEmpty == false }
}
