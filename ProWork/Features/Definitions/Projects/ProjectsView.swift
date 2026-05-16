//
//  ProjectsView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = ProjectsViewModel()

    @State private var isShowingCreateForm = false
    @State private var editingProject: ProjectListItem?
    @State private var pricingProject: ProjectListItem?
    @State private var confirmation: ProWorkConfirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            header
            projectList
        }
        .padding(ProWorkLayout.scaled(24, using: settingsStore))
        .proWorkFrame(minWidth: 920, minHeight: 600)
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear {
            viewModel.load(settingsStore: settingsStore)
        }
        .sheet(isPresented: $isShowingCreateForm) {
            ProjectFormView(
                mode: .create,
                customers: viewModel.customers
            ) { project in
                if viewModel.create(project, settingsStore: settingsStore) {
                    isShowingCreateForm = false
                }
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectFormView(
                mode: .edit(project),
                customers: viewModel.customers
            ) { updatedProject in
                if viewModel.update(updatedProject, settingsStore: settingsStore) {
                    editingProject = nil
                }
            }
        }
        .sheet(item: $pricingProject) { project in
            ScopedPriceListsView(
                ownerType: .project,
                ownerId: project.id,
                ownerLabel: "\(project.customerName) — \(project.name)",
                defaultCurrency: viewModel.projectCurrencies[project.id] ?? "TRY"
            )
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("projects.title", defaultValue: "Projeler"))
                    .proWorkTextStyle(.largeTitle)
                    .bold()

                Text(settingsStore.localized("projects.subtitle", defaultValue: "Müşteri bazlı proje kartları ve proje varsayılanları."))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isShowingCreateForm = true
            } label: {
                ProWorkButtonLabel(title: settingsStore.localized("projects.action.new", defaultValue: "Yeni Proje"), systemImage: "plus", minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.customers.isEmpty)
            .help(viewModel.customers.isEmpty ? settingsStore.localized("projects.help.needCustomer", defaultValue: "Önce müşteri eklemelisiniz") : settingsStore.localized("projects.help.new", defaultValue: "Yeni proje ekle"))
        }
    }

    private var projectList: some View {
        ZStack {
            if viewModel.customers.isEmpty {
                emptyState(
                    systemImage: "person.crop.circle.badge.plus",
                    title: settingsStore.localized("projects.empty.needCustomer.title", defaultValue: "Önce müşteri ekleyin"),
                    message: settingsStore.localized("projects.empty.needCustomer.message", defaultValue: "Proje oluşturabilmek için en az bir müşteri kartı gerekir.")
                )
            } else if viewModel.projects.isEmpty {
                emptyState(
                    systemImage: "folder.badge.plus",
                    title: settingsStore.localized("projects.empty.title", defaultValue: "Henüz proje yok"),
                    message: settingsStore.localized("projects.empty.message", defaultValue: "Sağ üstten yeni proje oluşturabilirsiniz.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                        ForEach(viewModel.projects) { project in
                            ProjectRowView(
                                project: project,
                                vatLabel: project.vatRateId.flatMap { viewModel.vatLabelsById[$0] },
                                onEdit: {
                                    editingProject = project
                                },
                                onPricing: {
                                    pricingProject = project
                                },
                                onDelete: {
                                    askDeleteProject(project)
                                }
                            )
                        }
                    }
                }
            }
        }
        .proWorkFrame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func emptyState(
        systemImage: String,
        title: String,
        message: String
    ) -> some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .proWorkFont(size: 34)
                .foregroundStyle(.secondary)

            Text(title)
                .proWorkTextStyle(.title2)
                .bold()

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .proWorkFrame(maxWidth: 420)
    }

    private func askDeleteProject(_ project: ProjectListItem) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("projects.delete.title", defaultValue: "Proje silinsin mi?"),
            message: String(format: settingsStore.localized("projects.delete.message", defaultValue: "“%@” projesi silinecek. Bu işlem geri alınamaz."), project.name),
            confirmTitle: settingsStore.localized("projects.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("projects.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.delete(id: project.id, settingsStore: settingsStore)
        }
    }
}
