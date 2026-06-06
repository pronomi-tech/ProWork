//  ProWorkSearchPickerField.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct ProWorkSearchPickerField<Item: Identifiable>: View where Item.ID == String {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let placeholder: String
    let items: [Item]
    @Binding var selectedId: String
    let isDisabled: Bool
    let systemImage: String
    let showsSearch: Bool
    let allowsClearingSelection: Bool

    let itemTitle: (Item) -> String
    let itemSubtitle: (Item) -> String?
    let itemColor: (Item) -> Color?
    let matchesSearch: (Item, String) -> Bool

    @State private var isShowingPicker = false
    @State private var searchText = ""

    init(
        title: String = "",
        placeholder: String,
        items: [Item],
        selectedId: Binding<String>,
        isDisabled: Bool = false,
        showsSearch: Bool = true,
        allowsClearingSelection: Bool = false,
        systemImage: String = "list.bullet",
        itemTitle: @escaping (Item) -> String,
        itemSubtitle: @escaping (Item) -> String? = { _ in nil },
        itemColor: @escaping (Item) -> Color? = { _ in nil },
        matchesSearch: @escaping (Item, String) -> Bool
    ) {
        self.title = title
        self.placeholder = placeholder
        self.items = items
        self._selectedId = selectedId
        self.isDisabled = isDisabled
        self.showsSearch = showsSearch
        self.allowsClearingSelection = allowsClearingSelection
        self.systemImage = systemImage
        self.itemTitle = itemTitle
        self.itemSubtitle = itemSubtitle
        self.itemColor = itemColor
        self.matchesSearch = matchesSearch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            if !title.isEmpty {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                guard !isDisabled else {
                    return
                }

                isShowingPicker.toggle()
            } label: {
                fieldContent
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
                pickerPopover
            }
        }
    }

    private var selectedItem: Item? {
        items.first { $0.id == selectedId }
    }

    private var filteredItems: [Item] {
        let cleanSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanSearch.isEmpty else {
            return items
        }

        return items.filter { item in
            matchesSearch(item, cleanSearch)
        }
    }

    private var fieldContent: some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: systemImage)
                .proWorkFont(size: 15)
                .foregroundStyle(.secondary)

            Text(selectedItem.map(itemTitle) ?? placeholder)
                .proWorkTextStyle(.callout)
                .foregroundStyle(selectedItem == nil ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.down")
                .proWorkFont(size: 12)
                .foregroundStyle(.secondary)
        }
        .proWorkFieldContainer(
            backgroundOpacity: isDisabled ? 0.35 : 0.70,
            alignment: .leading,
            fillsWidth: true,
            strokeColor: AnyShapeStyle(
                isShowingPicker ? Color.accentColor : Color.secondary.opacity(0.18)
            ),
            strokeLineWidth: isShowingPicker ? 1.4 : 1
        )
    }

    private var pickerPopover: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
                HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                    Image(systemName: systemImage)
                        .proWorkFont(size: 16, weight: .semibold)
                        .foregroundStyle(.blue)

                    Text(title.isEmpty ? placeholder : title)
                        .proWorkTextStyle(.headline)
                }

                Spacer()

                if allowsClearingSelection, selectedItem != nil {
                    Button {
                        selectedId = ""
                        searchText = ""
                        isShowingPicker = false
                    } label: {
                        headerActionIcon("arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(settingsStore.localized("common.clear", defaultValue: "Temizle"))
                }

                Button {
                    isShowingPicker = false
                } label: {
                    headerActionIcon("xmark")
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            if showsSearch {
                searchBar
            }

            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                        ForEach(filteredItems) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.vertical, ProWorkLayout.scaled(2, using: settingsStore))
                }
                .frame(height: ProWorkLayout.scaled(showsSearch ? 260 : 300, using: settingsStore))
            }
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(560, using: settingsStore))
    }

    private var searchBar: some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: "magnifyingglass")
                .proWorkFont(size: 15)
                .foregroundStyle(.secondary)

            TextField(settingsStore.localized("search.placeholder", defaultValue: "Ara"), text: $searchText)
                .textFieldStyle(.plain)
                .font(
                    ProWorkFonts.font(
                        size: 15,
                        weight: .regular,
                        using: settingsStore
                    )
                )

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .proWorkFont(size: 15)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(10, using: settingsStore))
        .frame(
            maxWidth: .infinity,
            minHeight: ProWorkLayout.scaled(42, using: settingsStore),
            alignment: .center
        )
        .background(.background.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func headerActionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .proWorkFont(size: 16)
            .foregroundStyle(.secondary)
            .frame(width: ProWorkLayout.scaled(18, using: settingsStore), height: ProWorkLayout.scaled(18, using: settingsStore))
            .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            Image(systemName: "magnifyingglass")
                .proWorkFont(size: 24)
                .foregroundStyle(.secondary)

            Text(settingsStore.localized("search.empty.title", defaultValue: "Sonuç bulunamadı"))
                .proWorkTextStyle(.headline)

            Text(settingsStore.localized("search.empty.message", defaultValue: "Arama metnini değiştirin veya yeni kayıt ekleyin."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ProWorkLayout.scaled(170, using: settingsStore),
            alignment: .center
        )
    }

    private func itemRow(_ item: Item) -> some View {
        let isSelected = selectedId == item.id

        return Button {
            selectedId = item.id
            searchText = ""
            isShowingPicker = false
        } label: {
            HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
                if let color = itemColor(item) {
                    Circle()
                        .fill(color)
                        .frame(
                            width: ProWorkLayout.scaled(10, using: settingsStore),
                            height: ProWorkLayout.scaled(10, using: settingsStore)
                        )
                }

                VStack(alignment: .leading, spacing: ProWorkLayout.scaled(3, using: settingsStore)) {
                    Text(itemTitle(item))
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = itemSubtitle(item), !subtitle.isEmpty {
                        Text(subtitle)
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: ProWorkLayout.scaled(12, using: settingsStore))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .proWorkFont(size: 16)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(10, using: settingsStore))
            .frame(
                maxWidth: .infinity,
                minHeight: ProWorkLayout.scaled(48, using: settingsStore),
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                    .stroke(
                        isSelected ? Color.blue.opacity(0.35) : Color.secondary.opacity(0.10),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
