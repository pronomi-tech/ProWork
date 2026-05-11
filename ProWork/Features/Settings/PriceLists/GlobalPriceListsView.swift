//
//  GlobalPriceListsView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct GlobalPriceListsView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var lists: [PriceList] = []
    @State private var rowsByListId: [String: [PriceListRow]] = [:]
    @State private var isShowingNewList = false
    @State private var editingList: PriceList?
    @State private var openListId: String?
    @State private var selectedListId: String?
    @State private var confirmation: ProWorkConfirmation?
    @State private var errorMessage: String?

    private let listRepository = PriceListRepository()
    private let rowRepository = PriceListRowRepository()

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("priceLists.global.title", defaultValue: "Genel Fiyat Listeleri"),
            subtitle: settingsStore.localized("priceLists.global.subtitle", defaultValue: "Varsayılan fiyat listeleri. Her liste birden fazla satır içerebilir."),
            errorMessage: errorMessage,
            toolbar: {
                HStack(spacing: 10) {
                    Button {
                        isShowingNewList = true
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("priceLists.action.newList", defaultValue: "Yeni Liste"), systemImage: "plus", minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    
                    Button {
                        if let id = selectedListId {
                            openListId = id
                        }
                    } label: {
                        ProWorkButtonLabel(title: settingsStore.localized("priceLists.action.editRows", defaultValue: "Satırları Düzenle"), systemImage: "list.bullet.indent", minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(selectedListId == nil)
                    .help(selectedListId == nil ? settingsStore.localized("priceLists.help.selectListFirst", defaultValue: "Önce listeden bir kayıt seçin") : settingsStore.localized("priceLists.help.editSelectedRows", defaultValue: "Seçili listenin satırlarını düzenle"))
                }
            }
        ) {
            if globalLists.isEmpty {
                SettingsCard {
                    SettingsEmptyState(
                        systemImage: "list.bullet.rectangle.portrait",
                        title: settingsStore.localized("priceLists.empty.title", defaultValue: "Henüz fiyat listesi yok"),
                        message: settingsStore.localized("priceLists.global.empty.message", defaultValue: "Sağ üstten yeni liste oluşturup içine fiyat satırları ekleyebilirsiniz.")
                    )
                }
            } else {
                listTable
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $isShowingNewList) {
            PriceListMetaFormView(mode: .create) { list in
                createList(list)
            }
        }
        .sheet(item: $editingList) { list in
            PriceListMetaFormView(mode: .edit(list)) { updated in
                updateList(updated)
            }
        }
        .sheet(item: openListBinding) { listId in
            if let list = lists.first(where: { $0.id == listId.id }) {
                PriceListRowsEditView(list: list) {
                    load()
                }
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var globalLists: [PriceList] {
        lists.filter { $0.ownerType == .global }
    }

    private var listTable: some View {
        SettingsTableContainer {
            tableHeader
            Divider()
            ForEach(globalLists) { list in
                row(list)
                Divider()
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("priceLists.column.name", defaultValue: "Ad")).frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("priceLists.column.currency", defaultValue: "Para Birimi")).frame(width: 110, alignment: .leading)
            Text(settingsStore.localized("priceLists.column.rows", defaultValue: "Satır")).frame(width: 60, alignment: .trailing)
            Text(settingsStore.localized("priceLists.column.active", defaultValue: "Aktif")).frame(width: 60, alignment: .center)
            Text("").frame(width: 90)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func row(_ list: PriceList) -> some View {
        let count = rowsByListId[list.id]?.count ?? 0
        let isSelected = selectedListId == list.id

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .proWorkTextStyle(.callout, weight: .medium)
                    .lineLimit(1)
                if let notes = list.notes, !notes.isEmpty {
                    Text(notes)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(list.currency)
                .proWorkTextStyle(.callout)
                .frame(width: 110, alignment: .leading)

            Text("\(count)")
                .proWorkTextStyle(.callout)
                .frame(width: 60, alignment: .trailing)

            Image(systemName: list.isActive ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(list.isActive ? .green : .secondary)
                .frame(width: 60, alignment: .center)

            HStack(spacing: 6) {
                Button {
                    editingList = list
                } label: {
                    Image(systemName: "pencil").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button {
                    askDelete(list)
                } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedListId = list.id
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                selectedListId = list.id
                openListId = list.id
            }
        )
    }

    // MARK: - Sheet identity helper

    private struct OpenListIdentity: Identifiable, Hashable {
        let id: String
    }

    private var openListBinding: Binding<OpenListIdentity?> {
        Binding(
            get: { openListId.map(OpenListIdentity.init) },
            set: { openListId = $0?.id }
        )
    }

    // MARK: - Actions

    private func load() {
        do {
            let all = try listRepository.fetchAll(organizationId: BuiltInOrganizationId.default)
            lists = all
            var bucket: [String: [PriceListRow]] = [:]
            for list in all {
                bucket[list.id] = (try? rowRepository.fetchAll(priceListId: list.id)) ?? []
            }
            rowsByListId = bucket
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createList(_ list: PriceList) {
        do {
            try listRepository.insert(list)
            isShowingNewList = false
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateList(_ list: PriceList) {
        do {
            try listRepository.update(list)
            editingList = nil
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askDelete(_ list: PriceList) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("priceLists.delete.title", defaultValue: "Fiyat listesi silinsin mi?"),
            message: String(format: settingsStore.localized("priceLists.delete.message", defaultValue: "\"%@\" silinecek. İçindeki tüm satırlar da silinir."), list.name),
            confirmTitle: settingsStore.localized("priceLists.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("priceLists.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            delete(list)
        }
    }

    private func delete(_ list: PriceList) {
        do {
            try listRepository.softDelete(id: list.id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
