//  ScopedPriceListsView.swift
//  ProWork
//  Created by Pronomi.
//  Generic screen managing price lists for a specific owner (Customer or Project).
//  CustomerPricingSheet and ProjectPricingSheet both use this view.

import SwiftUI

struct ScopedPriceListsView: View {
    let ownerType: PriceListOwnerType
    let ownerId: String
    let ownerLabel: String
    let defaultCurrency: String
    let onListsChanged: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var lists: [PriceList] = []
    @State private var rowsByListId: [String: [PriceListRow]] = [:]
    @State private var isShowingNewList = false
    @State private var editingList: PriceList?
    @State private var openListId: String?
    @State private var selectedListId: String?
    @State private var confirmation: ProWorkConfirmation?
    @State private var errorMessage: String?

    // Repositories are taken from AppServices so that a new instance is not
    // created every time the view struct is recreated.
    private let listRepository = AppServices.shared.priceListRepository
    private let rowRepository = AppServices.shared.priceListRowRepository

    init(
        ownerType: PriceListOwnerType,
        ownerId: String,
        ownerLabel: String,
        defaultCurrency: String,
        onListsChanged: (() -> Void)? = nil
    ) {
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.ownerLabel = ownerLabel
        self.defaultCurrency = defaultCurrency
        self.onListsChanged = onListsChanged
    }

    var body: some View {
        ProWorkFormShell(
            title: settingsStore.localized("priceLists.scoped.title", defaultValue: "Fiyat Listesi"),
            subtitle: String(format: settingsStore.localized("priceLists.scoped.subtitle", defaultValue: "%@ — %@"), ownerType.title, ownerLabel),
            systemImage: "list.bullet.rectangle.portrait",
            width: 1000,
            height: 660,
            contentScrollBehavior: .fixed,
            headerTrailing: {
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
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                infoBanner

                listTable
            }
        } footer: {
            SettingsFormSingleFooter(onPrimary: { dismiss() }, title: settingsStore.localized("common.close", defaultValue: "Kapat"), systemImage: "xmark")
        }
        .proWorkToastNotifications(errorMessage: errorMessage)
        .onAppear { load() }
        .sheet(isPresented: $isShowingNewList) {
            PriceListMetaFormView(
                mode: .create,
                ownerType: ownerType,
                ownerId: ownerId
            ) { list in
                createList(list)
            }
        }
        .sheet(item: $editingList) { list in
            PriceListMetaFormView(
                mode: .edit(list),
                ownerType: ownerType,
                ownerId: ownerId
            ) { updated in
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

    // MARK: - UI

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(scopeDescription)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var scopeDescription: String {
        switch ownerType {
        case .global:
            return settingsStore.localized("priceLists.scope.global", defaultValue: "Bu liste tüm müşteriler için varsayılandır.")
        case .customer:
            return settingsStore.localized("priceLists.scope.customer", defaultValue: "Bu liste sadece bu müşteriye uygulanır. Genel listeden öncelikli, projeden düşük önceliklidir.")
        case .project:
            return settingsStore.localized("priceLists.scope.project", defaultValue: "Bu liste sadece bu projeye uygulanır. Müşteri ve genel listelerin üstünde en yüksek önceliklidir.")
        }
    }

    private var listTable: some View {
        ProWorkGrid(
            items: lists,
            header: { tableHeader },
            emptyContent: {
                ProWorkGridEmptyState(
                    systemImage: "list.bullet.rectangle.portrait",
                    title: emptyTitle,
                    message: settingsStore.localized("priceLists.scoped.empty.message", defaultValue: "Bir liste oluşturup içine fiyat satırları ekleyebilirsiniz.")
                )
            },
            row: { list in row(list) }
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("priceLists.column.name", defaultValue: "Ad")).frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("priceLists.column.currency", defaultValue: "Para Birimi")).frame(width: 110, alignment: .leading)
            Text(settingsStore.localized("priceLists.column.default", defaultValue: "Varsayılan")).frame(width: 90, alignment: .center)
            Text(settingsStore.localized("priceLists.column.rows", defaultValue: "Satır")).frame(width: 60, alignment: .trailing)
            Text(settingsStore.localized("priceLists.column.active", defaultValue: "Aktif")).frame(width: 90, alignment: .leading)
            Color.gridHeaderSpacer(width: 90)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35))
    }

    private func row(_ list: PriceList) -> some View {
        let count = rowsByListId[list.id]?.count ?? 0
        let isSelected = selectedListId == list.id

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .proWorkTextStyle(.callout, weight: .medium)
                if let notes = list.notes {
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

            Text(list.isDefault ? settingsStore.localized("priceLists.defaultBadge", defaultValue: "Varsayılan") : settingsStore.localized("common.notAvailable", defaultValue: "—"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(list.isDefault ? .green : .secondary)
                .frame(width: 90, alignment: .center)

            Text("\(count)")
                .proWorkTextStyle(.callout)
                .frame(width: 60, alignment: .trailing)

            ProWorkActivityBadge(isActive: list.isActive)
                .frame(width: 90, alignment: .leading)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

    private var emptyTitle: String {
        switch ownerType {
        case .global:
            return settingsStore.localized("priceLists.scoped.empty.global", defaultValue: "Henüz genel fiyat listesi yok")
        case .customer:
            return settingsStore.localized("priceLists.scoped.empty.customer", defaultValue: "Henüz müşteri fiyat listesi yok")
        case .project:
            return settingsStore.localized("priceLists.scoped.empty.project", defaultValue: "Henüz proje fiyat listesi yok")
        }
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

    /// Routed through `PriceListsLoader`.
    private func load() {
        do {
            let result = try PriceListsLoader.load(
                organizationId: BuiltInOrganizationId.default,
                ownerType: ownerType,
                ownerId: ownerId,
                listRepository: listRepository,
                rowRepository: rowRepository
            )
            lists = result.lists
            rowsByListId = result.rowsByListId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createList(_ list: PriceList) {
        // Currency default may be the parent's default
        var copy = list
        if copy.currency.isEmpty {
            copy.currency = defaultCurrency
        }
        do {
            try listRepository.insert(copy)
            isShowingNewList = false
            load()
            onListsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateList(_ list: PriceList) {
        do {
            try listRepository.update(list)
            editingList = nil
            load()
            onListsChanged?()
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
            try listRepository.softDelete(id: list.id, by: AppServices.currentUserId)
            load()
            onListsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
