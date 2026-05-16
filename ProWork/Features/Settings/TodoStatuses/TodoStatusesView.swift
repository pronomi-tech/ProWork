//
//  TodoStatusesView.swift
//  ProWork
//
//  Created by Pronomi.
//

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
            toolbar: {
                Button {
                    isShowingCreateForm = true
                } label: {
                    ProWorkButtonLabel(title: settingsStore.localized("todoStatuses.action.new", defaultValue: "Yeni Statü"), systemImage: "plus", minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        ) {
            statusTable
        }
        .onAppear {
            viewModel.load()
        }
        .sheet(isPresented: $isShowingCreateForm) {
            TodoStatusFormView(mode: .create) { status in
                if viewModel.create(status) {
                    isShowingCreateForm = false
                }
            }
        }
        .sheet(item: $editingStatus) { status in
            TodoStatusFormView(mode: .edit(status)) { updatedStatus in
                if viewModel.update(updatedStatus) {
                    editingStatus = nil
                }
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var statusTable: some View {
        SettingsTableContainer {
            tableHeader

            Divider()

            if viewModel.statuses.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.statuses) { status in
                            TodoStatusCompactRowView(
                                status: status,
                                onEdit: {
                                    editingStatus = status
                                },
                                onDelete: {
                                    askDeleteStatus(status)
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

            Text(settingsStore.localized("todoStatuses.column.status", defaultValue: "Statü"))
                .proWorkFrame(maxWidth: .infinity, alignment: .leading)

            Text(settingsStore.localized("todoStatuses.column.order", defaultValue: "Sıra"))
                .proWorkFrame(width: 50, alignment: .trailing)

            Text(settingsStore.localized("todoStatuses.column.behavior", defaultValue: "Davranış"))
                .proWorkFrame(width: 340, alignment: .leading)

            Text(settingsStore.localized("todoStatuses.column.source", defaultValue: "Kaynak"))
                .proWorkFrame(width: 70, alignment: .leading)

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
            Image(systemName: "rectangle.3.group")
                .proWorkFont(size: 28)
                .foregroundStyle(.secondary)

            Text(settingsStore.localized("todoStatuses.empty.title", defaultValue: "Henüz iş akışı statüsü yok"))
                .proWorkTextStyle(.headline)

            Text(settingsStore.localized("todoStatuses.empty.message", defaultValue: "Sağ üstten yeni statü oluşturabilirsiniz."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .proWorkFrame(minHeight: 220, maxWidth: .infinity)
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
