//  HolidaysView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct HolidaysView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = HolidaysViewModel()

    @State private var selectedYear: Int = AppCalendar.istanbul.component(.year, from: Date())
    @State private var isShowingCreate = false
    @State private var editingHoliday: Holiday?
    @State private var confirmation: ProWorkConfirmation?
    /// Cache backings.
    @State private var cachedAvailableYears: [Int] = []
    @State private var cachedFilteredHolidays: [Holiday] = []

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("holidays.title", defaultValue: "Resmi Tatiller"),
            subtitle: settingsStore.localized("holidays.subtitle", defaultValue: "Tatil günlerinde yapılan çalışmalar 'Tatil' zaman tipi olarak ücretlendirilir. 2025–2030 TR tatilleri ön-yüklü gelir; düzenleyebilir, ekleyebilir veya silebilirsiniz."),
            errorMessage: viewModel.errorMessage,
            contentScrollBehavior: .fixed,
            toolbar: {
                SettingsCRUDToolbarButton(
                    title: settingsStore.localized("holidays.action.new", defaultValue: "Yeni Tatil"),
                    systemImage: "plus"
                ) {
                    isShowingCreate = true
                }
            }
        ) {
            yearPicker

            holidayTable
        }
        .onAppear {
            viewModel.load()
            rebuildHolidayCaches()
        }
        .onChange(of: viewModel.holidays) { _, _ in rebuildHolidayCaches() }
        .onChange(of: selectedYear) { _, _ in rebuildHolidayCaches() }
        .settingsCRUDPresenter(
            isShowingCreate: $isShowingCreate,
            editingItem: $editingHoliday,
            confirmation: $confirmation,
            createForm: {
                HolidayFormView(mode: .create) { holiday in
                    if viewModel.create(holiday) {
                        isShowingCreate = false
                    }
                }
            },
            editForm: { holiday in
                HolidayFormView(mode: .edit(holiday)) { updated in
                    if viewModel.update(updated) {
                        editingHoliday = nil
                    }
                }
            }
        )
    }

    private var yearPicker: some View {
        HStack(spacing: 6) {
            ForEach(availableYears, id: \.self) { year in
                Button {
                    selectedYear = year
                } label: {
                    Text(String(year))
                        .proWorkTextStyle(.callout, weight: selectedYear == year ? .semibold : .regular)
                        .foregroundStyle(selectedYear == year ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedYear == year ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(String(format: settingsStore.localized("holidays.dayCount", defaultValue: "%d gün"), filteredHolidays.count))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Cache `availableYears` and `filteredHolidays` so they
    /// rebuild only on the inputs that affect them. The computed
    /// versions rebuilt on every body eval (year picker change,
    /// holiday import progress) and scanned all holidays each time.
    private var availableYears: [Int] {
        cachedAvailableYears
    }

    private var filteredHolidays: [Holiday] {
        cachedFilteredHolidays
    }

    private func rebuildHolidayCaches() {
        let years = Set(viewModel.holidays.compactMap {
            $0.dateString.split(separator: "-").first.flatMap { Int($0) }
        })
        let now = AppCalendar.istanbul.component(.year, from: Date())
        let allRange = Set((now - 1)...(now + 4))
        cachedAvailableYears = Array(years.union(allRange)).sorted()

        cachedFilteredHolidays = viewModel.holidays
            .filter { $0.dateString.hasPrefix("\(selectedYear)-") }
            .sorted { $0.dateString < $1.dateString }
    }

    private var holidayTable: some View {
        ProWorkGrid(
            items: filteredHolidays,
            header: { tableHeader },
            emptyContent: {
                ProWorkGridEmptyState(
                    systemImage: "calendar",
                    title: String(format: settingsStore.localized("holidays.empty.year", defaultValue: "%d için tatil yok"), selectedYear),
                    message: settingsStore.localized("holidays.empty.message", defaultValue: "Sağ üstten yeni tatil ekleyebilirsiniz.")
                )
            },
            row: { holiday in row(holiday) }
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("holidays.column.date", defaultValue: "Tarih")).frame(width: 130, alignment: .leading)
            Text(settingsStore.localized("holidays.column.name", defaultValue: "Ad")).frame(maxWidth: .infinity, alignment: .leading)
            Text(settingsStore.localized("holidays.column.type", defaultValue: "Tip")).frame(width: 130, alignment: .leading)
            Text(settingsStore.localized("holidays.column.active", defaultValue: "Aktif")).frame(width: 90, alignment: .leading)
            Color.gridHeaderSpacer(width: 76)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func formatDate(_ holiday: Holiday) -> String {
        if let date = holiday.date {
            return settingsStore.formatDate(date)
        }
        return holiday.dateString
    }

    private func row(_ holiday: Holiday) -> some View {
        HStack(spacing: 12) {
            Text(formatDate(holiday))
                .proWorkTextStyle(.callout)
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(holiday.isActive ? .primary : .secondary)

            Text(holiday.name)
                .proWorkTextStyle(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(holiday.isActive ? .primary : .secondary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: holiday.isHalfDay ? "clock.badge.questionmark" : "calendar")
                    .proWorkFont(size: 12)
                Text(holiday.isHalfDay ? settingsStore.localized("holidays.type.halfDay", defaultValue: "Yarım gün") : settingsStore.localized("holidays.type.fullDay", defaultValue: "Tam gün"))
                    .proWorkTextStyle(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(width: 130, alignment: .leading)

            ProWorkActivityBadge(isActive: holiday.isActive)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 6) {
                Button { editingHoliday = holiday } label: {
                    Image(systemName: "pencil").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button { askDelete(holiday) } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func askDelete(_ holiday: Holiday) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("holidays.delete.title", defaultValue: "Tatil silinsin mi?"),
            message: String(format: settingsStore.localized("holidays.delete.message", defaultValue: "\"%@\" (%@) silinecek."), holiday.name, holiday.dateString),
            confirmTitle: settingsStore.localized("holidays.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("holidays.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            viewModel.softDelete(id: holiday.id)
        }
    }
}
