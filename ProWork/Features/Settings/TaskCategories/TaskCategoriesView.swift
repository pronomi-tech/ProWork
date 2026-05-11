//
//  TaskCategoriesView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct TaskCategoriesView: View {
    @State private var categories: [TaskCategory] = []
    @State private var vatLabelsById: [String: String] = [:]
    @State private var isShowingCreateForm = false
    @State private var editingCategory: TaskCategory?
    @State private var confirmation: ProWorkConfirmation?
    @State private var errorMessage: String?
    @EnvironmentObject private var settingsStore: AppSettingsStore

    private let repository = TaskCategoryRepository()
    private let vatRateRepository = VatRateRepository()

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("taskCategories.title", defaultValue: "Görev Kategorileri"),
            subtitle: settingsStore.localized("taskCategories.subtitle", defaultValue: "Todo, zaman kaydı ve raporlarda kullanılacak görev kategorilerini yönetin."),
            errorMessage: errorMessage,
            toolbar: {
                Button {
                    isShowingCreateForm = true
                } label: {
                    ProWorkButtonLabel(title: settingsStore.localized("taskCategories.action.new", defaultValue: "Yeni Kategori"), systemImage: "plus", minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        ) {
            categoryTable
        }
        .onAppear {
            loadCategories()
        }
        .sheet(isPresented: $isShowingCreateForm) {
            TaskCategoryFormView(mode: .create) { category in
                createCategory(category)
            }
        }
        .sheet(item: $editingCategory) { category in
            TaskCategoryFormView(mode: .edit(category)) { updatedCategory in
                updateCategory(updatedCategory)
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var categoryTable: some View {
        SettingsTableContainer {
            tableHeader

            Divider()

            if categories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(categories) { category in
                            TaskCategoryCompactRowView(
                                category: category,
                                vatLabel: category.vatRateId.flatMap { vatLabelsById[$0] },
                                onEdit: {
                                    editingCategory = category
                                },
                                onDelete: {
                                    askDeleteCategory(category)
                                }
                            )

                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("")
                .proWorkFrame(width: 24)

            Text(settingsStore.localized("taskCategories.column.name", defaultValue: "Ad"))
                .proWorkFrame(maxWidth: .infinity, alignment: .leading)

            Text(settingsStore.localized("taskCategories.column.type", defaultValue: "Tip"))
                .proWorkFrame(width: 150, alignment: .leading)

            Text(settingsStore.localized("taskCategories.column.order", defaultValue: "Sıra"))
                .proWorkFrame(width: 60, alignment: .trailing)

            Text(settingsStore.localized("taskCategories.column.source", defaultValue: "Kaynak"))
                .proWorkFrame(width: 90, alignment: .leading)

            Text("")
                .proWorkFrame(width: 72)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag")
                .proWorkFont(size: 28)
                .foregroundStyle(.secondary)

            Text(settingsStore.localized("taskCategories.empty.title", defaultValue: "Henüz kategori yok"))
                .proWorkTextStyle(.headline)

            Text(settingsStore.localized("taskCategories.empty.message", defaultValue: "Sağ üstten yeni görev kategorisi oluşturabilirsiniz."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .proWorkFrame(minHeight: 220, maxWidth: .infinity)
    }

    private func loadCategories() {
        do {
            categories = try repository.fetchAll()
            let vatRates = try vatRateRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            vatLabelsById = VatRateLabel.nonDefaultSelectionLabels(
                rates: vatRates,
                settingsStore: settingsStore
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createCategory(_ category: TaskCategory) {
        do {
            try repository.insert(category)
            loadCategories()
            isShowingCreateForm = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateCategory(_ category: TaskCategory) {
        do {
            try repository.update(category)
            loadCategories()
            editingCategory = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askDeleteCategory(_ category: TaskCategory) {
        guard !category.isSystem else {
            return
        }

        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("taskCategories.delete.title", defaultValue: "Görev kategorisi silinsin mi?"),
            message: String(format: settingsStore.localized("taskCategories.delete.message", defaultValue: "“%@” görev kategorisi silinecek. Bu işlem geri alınamaz."), category.name),
            confirmTitle: settingsStore.localized("taskCategories.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("taskCategories.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            deleteCategory(category)
        }
    }

    private func deleteCategory(_ category: TaskCategory) {
        do {
            try repository.delete(id: category.id)
            loadCategories()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
