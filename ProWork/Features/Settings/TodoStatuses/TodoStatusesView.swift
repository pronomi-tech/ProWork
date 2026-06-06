//  TodoStatusesView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct TodoStatusesView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = TodoStatusesViewModel()

    @State private var isShowingCreateForm = false
    @State private var editingStatus: TodoStatus?
    @State private var confirmation: ProWorkConfirmation?

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("todoStatuses.title", defaultValue: "İş Akışı Statüleri"),
            subtitle: settingsStore.localized("todoStatuses.subtitle", defaultValue: "Yapılacak listesi kolonları, görünürlük ve süre başlatma/durdurma davranışlarını yönetin."),
            errorMessage: viewModel.errorMessage,
            contentScrollBehavior: .fixed,
            toolbar: {
                SettingsCRUDToolbarButton(
                    title: settingsStore.localized("todoStatuses.action.new", defaultValue: "Yeni Statü"),
                    systemImage: "plus"
                ) {
                    isShowingCreateForm = true
                }
            }
        ) {
            statusTable
        }
        .onAppear {
            viewModel.load()
        }
        .settingsCRUDPresenter(
            isShowingCreate: $isShowingCreateForm,
            editingItem: $editingStatus,
            confirmation: $confirmation,
            createForm: {
                TodoStatusFormView(mode: .create) { status in
                    if viewModel.create(status) {
                        isShowingCreateForm = false
                    }
                }
            },
            editForm: { status in
                TodoStatusFormView(mode: .edit(status)) { updatedStatus in
                    if viewModel.update(updatedStatus) {
                        editingStatus = nil
                    }
                }
            }
        )
    }

    private var statusTable: some View {
        ProWorkGrid(
            items: viewModel.statuses,
            header: { tableHeader },
            emptyContent: {
                ProWorkGridEmptyState(
                    systemImage: "rectangle.3.group",
                    title: settingsStore.localized("todoStatuses.empty.title", defaultValue: "Henüz iş akışı statüsü yok"),
                    message: settingsStore.localized("todoStatuses.empty.message", defaultValue: "Sağ üstten yeni statü oluşturabilirsiniz.")
                )
            },
            row: { status in
                TodoStatusCompactRowView(
                    status: status,
                    onEdit: { editingStatus = status },
                    onDelete: { askDeleteStatus(status) }
                )
            }
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Color.gridHeaderSpacer(width: 24)

            Text(settingsStore.localized("todoStatuses.column.status", defaultValue: "Statü"))
                .proWorkFrame(maxWidth: .infinity, alignment: .leading)

            Text(settingsStore.localized("todoStatuses.column.order", defaultValue: "Sıra"))
                .proWorkFrame(width: 50, alignment: .trailing)

            Text(settingsStore.localized("todoStatuses.column.behavior", defaultValue: "Davranış"))
                .proWorkFrame(width: 340, alignment: .leading)

            Text(settingsStore.localized("todoStatuses.column.source", defaultValue: "Kaynak"))
                .proWorkFrame(width: 70, alignment: .leading)

            Color.gridHeaderSpacer(width: 72)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35))
    }

    private func askDeleteStatus(_ status: TodoStatus) {
        guard !status.isSystem else { return }

        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("todoStatuses.delete.title", defaultValue: "İş akışı statüsü silinsin mi?"),
            message: String(format: settingsStore.localized("todoStatuses.delete.message", defaultValue: "“%@” iş akışı statüsü silinecek. Bu işlem geri alınamaz."), status.name),
            confirmTitle: settingsStore.localized("todoStatuses.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("todoStatuses.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.delete(id: status.id)
        }
    }
}
