//
//  TaskCategoriesView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct TaskCategoriesView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = TaskCategoriesViewModel()

    @State private var isShowingCreateForm = false
    @State private var editingCategory: TaskCategory?
    @State private var confirmation: ProWorkConfirmation?

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("taskCategories.title", defaultValue: "Görev Kategorileri"),
            subtitle: settingsStore.localized("taskCategories.subtitle", defaultValue: "Todo, zaman kaydı ve raporlarda kullanılacak görev kategorilerini yönetin."),
            errorMessage: viewModel.errorMessage,
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
            viewModel.load(settingsStore: settingsStore)
        }
        .sheet(isPresented: $isShowingCreateForm) {
            TaskCategoryFormView(mode: .create) { category in
                if viewModel.create(category, settingsStore: settingsStore) {
                    isShowingCreateForm = false
                }
            }
        }
        .sheet(item: $editingCategory) { category in
            TaskCategoryFormView(mode: .edit(category)) { updatedCategory in
                if viewModel.update(updatedCategory, settingsStore: settingsStore) {
                    editingCategory = nil
                }
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var categoryTable: some View {
        SettingsTableContainer {
            tableHeader

            Divider()

            if viewModel.categories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.categories) { category in
                            TaskCategoryCompactRowView(
                                category: category,
                                vatLabel: category.vatRateId.flatMap { viewModel.vatLabelsById[$0] },
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

    private func askDeleteCategory(_ category: TaskCategory) {
        guard !category.isSystem else { return }

        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("taskCategories.delete.title", defaultValue: "Görev kategorisi silinsin mi?"),
            message: String(format: settingsStore.localized("taskCategories.delete.message", defaultValue: "“%@” görev kategorisi silinecek. Bu işlem geri alınamaz."), category.name),
            confirmTitle: settingsStore.localized("taskCategories.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("taskCategories.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.delete(id: category.id, settingsStore: settingsStore)
        }
    }
}
