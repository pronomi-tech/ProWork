//  ProjectsView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = ProjectsViewModel()

    @State private var isShowingCreateForm = false
    @State private var editingProject: ProjectListItem?
    @State private var pricingProject: ProjectListItem?
    @State private var confirmation: ProWorkConfirmation?

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("projects.title", defaultValue: "Projeler"),
            subtitle: settingsStore.localized("projects.subtitle", defaultValue: "Müşteri bazlı proje kartları ve proje varsayılanları."),
            errorMessage: viewModel.errorMessage,
            contentScrollBehavior: .fixed,
            toolbar: {
                SettingsCRUDToolbarButton(
                    title: settingsStore.localized("projects.action.new", defaultValue: "Yeni Proje"),
                    systemImage: "plus",
                    isDisabled: viewModel.customers.isEmpty,
                    disabledHelp: settingsStore.localized("projects.help.needCustomer", defaultValue: "Önce müşteri eklemelisiniz")
                ) {
                    isShowingCreateForm = true
                }
            }
        ) {
            projectList
        }
        .onAppear {
            viewModel.load()
        }
        .settingsCRUDPresenter(
            isShowingCreate: $isShowingCreateForm,
            editingItem: $editingProject,
            confirmation: $confirmation,
            createForm: {
                ProjectFormView(
                    mode: .create,
                    customers: viewModel.customers
                ) { project in
                    if viewModel.create(project) {
                        isShowingCreateForm = false
                    }
                }
            },
            editForm: { project in
                ProjectFormView(
                    mode: .edit(project),
                    customers: viewModel.customers
                ) { updatedProject in
                    if viewModel.update(updatedProject) {
                        editingProject = nil
                    }
                }
            }
        )
        // Pricing sheet — an additional flow outside the CRUDPresenter.
        .sheet(item: $pricingProject) { project in
            ScopedPriceListsView(
                ownerType: .project,
                ownerId: project.id,
                ownerLabel: "\(project.customerName) — \(project.name)",
                defaultCurrency: viewModel.projectCurrencies[project.id] ?? "TRY"
            )
        }
    }

    private var projectList: some View {
        ProWorkGrid(
            items: viewModel.projects,
            header: { tableHeader },
            emptyContent: {
                ProWorkGridEmptyState(
                    systemImage: viewModel.customers.isEmpty ? "person.crop.circle.badge.plus" : "folder.badge.plus",
                    title: viewModel.customers.isEmpty
                        ? settingsStore.localized("projects.empty.needCustomer.title", defaultValue: "Önce müşteri ekleyin")
                        : settingsStore.localized("projects.empty.title", defaultValue: "Henüz proje yok"),
                    message: viewModel.customers.isEmpty
                        ? settingsStore.localized("projects.empty.needCustomer.message", defaultValue: "Proje oluşturabilmek için en az bir müşteri kartı gerekir.")
                        : settingsStore.localized("projects.empty.message", defaultValue: "Sağ üstten yeni proje oluşturabilirsiniz.")
                )
            },
            row: { project in projectRow(project) }
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("projects.column.customer", defaultValue: "Müşteri"))
                .frame(width: 200, alignment: .leading)
            Text(settingsStore.localized("projects.column.project", defaultValue: "Proje"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("projects.column.code", defaultValue: "Kod"))
                .frame(width: 90, alignment: .leading)
            Text(settingsStore.localized("projects.column.status", defaultValue: "Durum"))
                .frame(width: 110, alignment: .leading)
            Text(settingsStore.localized("projects.column.currency", defaultValue: "Para Birimi"))
                .frame(width: 100, alignment: .leading)
            Text(settingsStore.localized("projects.column.vat", defaultValue: "KDV"))
                .frame(width: 130, alignment: .leading)
            Color.gridHeaderSpacer(width: 110)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func projectRow(_ project: ProjectListItem) -> some View {
        let currency = viewModel.projectCurrencies[project.id] ?? "TRY"
        let vatLabel = project.vatRateId.flatMap { viewModel.vatLabelsById[$0] } ?? "—"

        return HStack(spacing: 12) {
            Text(project.customerName)
                .proWorkTextStyle(.callout)
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .proWorkTextStyle(.callout, weight: .medium)
                    .lineLimit(1)
                if let notes = project.notes, !notes.isEmpty {
                    Text(notes)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(project.code ?? "—")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(project.status))
                    .frame(width: 8, height: 8)
                Text(statusTitle(project.status))
                    .proWorkTextStyle(.caption)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)

            Text(currency)
                .proWorkTextStyle(.callout)
                .frame(width: 100, alignment: .leading)

            Text(vatLabel)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    pricingProject = project
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help(settingsStore.localized("projects.action.pricing", defaultValue: "Fiyatlandırma"))

                Button {
                    editingProject = project
                } label: {
                    Image(systemName: "pencil").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button {
                    askDeleteProject(project)
                } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Returns a localised name instead of the raw "active" / "passive"
    /// string for a grid row. The same mapping exists in ProjectRowView;
    /// repeated here to stay consistent with the grid row-card appearance.
    private func statusTitle(_ value: String) -> String {
        switch value {
        case "passive":
            return settingsStore.localized("projects.status.passive", defaultValue: "Pasif")
        case "completed":
            return settingsStore.localized("projects.status.completed", defaultValue: "Tamamlandı")
        case "suspended":
            return settingsStore.localized("projects.status.suspended", defaultValue: "Askıda")
        default:
            return settingsStore.localized("projects.status.active", defaultValue: "Aktif")
        }
    }

    private func statusColor(_ value: String) -> Color {
        switch value {
        case "passive":
            return .secondary
        case "completed":
            return .blue
        case "suspended":
            return .orange
        default:
            return .green
        }
    }

    private func askDeleteProject(_ project: ProjectListItem) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("projects.delete.title", defaultValue: "Proje silinsin mi?"),
            message: String(format: settingsStore.localized("projects.delete.message", defaultValue: "“%@” projesi silinecek. Bu işlem geri alınamaz."), project.name),
            confirmTitle: settingsStore.localized("projects.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("projects.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.delete(id: project.id)
        }
    }
}
