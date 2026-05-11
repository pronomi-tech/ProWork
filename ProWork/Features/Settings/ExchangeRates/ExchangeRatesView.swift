//
//  ExchangeRatesView.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

private enum ExchangeRatesTab: String, CaseIterable, Identifiable {
    case tcmb
    case global
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tcmb: return ExchangeRateSource.tcmb.title
        case .global: return ExchangeRateSource.global.title
        case .manual: return ExchangeRateSource.manual.title
        }
    }

    var subtitle: String {
        switch self {
        case .tcmb:
            return ProWorkLocalizer.shared.string("exchangeRates.tab.tcmb.subtitle", defaultValue: "TCMB alış/satış ve efektif alış/satış kurları")
        case .global:
            return ProWorkLocalizer.shared.string("exchangeRates.tab.global.subtitle", defaultValue: "Global referans kur yedek kaynağı")
        case .manual:
            return ProWorkLocalizer.shared.string("exchangeRates.tab.manual.subtitle", defaultValue: "Elle eklenen kur kayıtları")
        }
    }

    var source: ExchangeRateSource {
        switch self {
        case .tcmb: return .tcmb
        case .global: return .global
        case .manual: return .manual
        }
    }

    var autoSource: ExchangeRateAutoSource? {
        switch self {
        case .tcmb: return .tcmb
        case .global: return .global
        case .manual: return nil
        }
    }
}

private enum ExchangeRateImportMode: String, CaseIterable, Identifiable {
    case today
    case range

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return ProWorkLocalizer.shared.string("exchangeRates.importMode.today", defaultValue: "Bugün")
        case .range: return ProWorkLocalizer.shared.string("exchangeRates.importMode.range", defaultValue: "Tarih Aralığı")
        }
    }
}

struct ExchangeRatesView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var rates: [ExchangeRate] = []
    @State private var isShowingNew = false
    @State private var selectedTab: ExchangeRatesTab = .tcmb
    @State private var isShowingFilters = false
    @State private var filterRange: DateRangeFilter = .all
    @State private var selectedCurrencyFilter: String = "ALL"
    @State private var filterCustomStart: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var filterCustomEnd: Date = Date()
    @State private var importMode: ExchangeRateImportMode = .today
    @State private var isShowingImportModePicker = false
    @State private var importStartDate: Date = Date()
    @State private var importEndDate: Date = Date()
    @State private var importingSource: ExchangeRateAutoSource?
    @State private var tableViewportWidth: CGFloat = 0
    @State private var editingRate: ExchangeRate?
    @State private var confirmation: ProWorkConfirmation?
    @State private var errorMessage: String?
    @State private var savedNotice: String?

    private let repository = ExchangeRateRepository()
    private let tcmbSyncService = TCMBExchangeRateSyncService()
    private let globalSyncService = GlobalExchangeRateSyncService()

    private var supportedCurrencyCodes: [String] {
        Currency.allCodes.filter { $0 != "TRY" }
    }

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("exchangeRates.title", defaultValue: "Döviz Kurları"),
            subtitle: settingsStore.localized("exchangeRates.subtitle", defaultValue: "Kayıtları kaynak bazında yönetin, seçili kaynaktan kur çekin ve aynı panel içinde filtreleyin."),
            errorMessage: errorMessage,
            savedNotice: savedNotice,
            contentScrollBehavior: .fixed
        ) {
            mainPanel
        }
        .onAppear {
            selectedTab = settingsStore.settings.preferredExchangeRateSource == .tcmb ? .tcmb : .global
            load()
        }
        .sheet(isPresented: $isShowingNew) {
            ExchangeRateFormView(mode: .create) { rate in
                add(rate)
            }
        }
        .sheet(item: $editingRate) { rate in
            ExchangeRateFormView(mode: .edit(rate)) { updated in
                update(updated)
            }
        }
        .proWorkConfirmationDialog($confirmation)
    }

    private var mainPanel: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(ExchangeRatesTab.allCases) { tab in
                        sourceTabButton(tab)
                    }
                    Spacer(minLength: 0)
                }

                Divider()

                switch selectedTab {
                case .tcmb:
                    importPanel(for: .tcmb)
                case .global:
                    importPanel(for: .global)
                case .manual:
                    manualPanel
                }

                Divider()

                filterBar

                if isShowingFilters {
                    filterPanel
                }

                if filteredRates.isEmpty {
                    SettingsEmptyState(
                        systemImage: "arrow.left.arrow.right.circle",
                        title: settingsStore.localized("exchangeRates.empty.title", defaultValue: "Kayıt bulunamadı"),
                        message: selectedTab == .manual
                            ? settingsStore.localized("exchangeRates.empty.manual", defaultValue: "Manuel tabında henüz kayıt yok veya filtre sonucu boş.")
                            : settingsStore.localized("exchangeRates.empty.filtered", defaultValue: "Seçili kaynak ve filtre için kur kaydı bulunamadı.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    table
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sourceTabButton(_ tab: ExchangeRatesTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.source.systemImage)
                    .proWorkFont(size: 12)

                Text(tab.title)
                    .proWorkTextStyle(.callout, weight: .medium)

                if tab.autoSource == settingsStore.settings.preferredExchangeRateSource {
                    Image(systemName: "checkmark.circle.fill")
                        .proWorkFont(size: 12)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func importPanel(for source: ExchangeRateAutoSource) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Text(source.title)
                        .proWorkTextStyle(.headline)

                    Button {
                        settingsStore.updatePreferredExchangeRateSource(source)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: settingsStore.settings.preferredExchangeRateSource == source ? "checkmark.circle.fill" : "circle")
                                .proWorkFont(size: 12)
                            Text(settingsStore.localized("exchangeRates.default", defaultValue: "Varsayılan"))
                                .proWorkTextStyle(.caption)
                        }
                        .foregroundStyle(settingsStore.settings.preferredExchangeRateSource == source ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(settingsStore.settings.preferredExchangeRateSource == source ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                importModeMenu

                if importMode == .range {
                    ProWorkDateField(title: "", date: $importStartDate)
                        .frame(width: 168)
                    ProWorkDateField(title: "", date: $importEndDate)
                        .frame(width: 168)
                }

                Button {
                    importRates(from: source)
                } label: {
                    if importingSource == source {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 84, height: 32)
                    } else {
                        ProWorkButtonLabel(
                            title: settingsStore.localized("exchangeRates.fetch", defaultValue: "Çek"),
                            systemImage: source.systemImage,
                            minHeight: 32
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(importingSource != nil)
            }

            Text(source.subtitle)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            Text(String(format: settingsStore.localized("exchangeRates.supportedCurrencies", defaultValue: "Çekilen para birimleri: %@"), supportedCurrencyCodes.joined(separator: ", ")))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var importModeMenu: some View {
        HStack(spacing: 8) {
            Text(importMode.title)
                .proWorkTextStyle(.caption)
            Image(systemName: "chevron.down")
                .proWorkFont(size: 10)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .onTapGesture {
            isShowingImportModePicker.toggle()
        }
        .popover(isPresented: $isShowingImportModePicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ExchangeRateImportMode.allCases) { mode in
                    HStack(spacing: 8) {
                        Image(systemName: importMode == mode ? "checkmark" : "circle")
                            .proWorkFont(size: 11)
                        Text(mode.title)
                            .proWorkTextStyle(.caption)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(importMode == mode ? Color.accentColor.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        applyImportMode(mode)
                        isShowingImportModePicker = false
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .frame(width: 180)
        }
    }

    private var manualPanel: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(settingsStore.localized("exchangeRates.source.manual", defaultValue: "Manuel"))
                    .proWorkTextStyle(.headline)
                Text(settingsStore.localized("exchangeRates.manual.subtitle", defaultValue: "Manuel kayıtlar yalnız desteklenen para birimlerinden TRY yönüne eklenir."))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isShowingNew = true
            } label: {
                ProWorkButtonLabel(title: settingsStore.localized("exchangeRates.manual.add", defaultValue: "Manuel Kur Ekle"), systemImage: "plus", minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var filterBar: some View {
        HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingFilters.toggle()
                }
            } label: {
                HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .proWorkFont(size: 15)
                        .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.secondary)

                    Text(settingsStore.localized("exchangeRates.filter", defaultValue: "Filtrele"))
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(hasActiveFilters ? Color.accentColor : Color.primary)
                }
                .padding(.horizontal, ProWorkLayout.scaled(12, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                .background(hasActiveFilters ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore)))
            }
            .buttonStyle(.plain)

            if hasActiveFilters {
                Button {
                    clearFilters()
                } label: {
                    HStack(spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                        Image(systemName: "xmark")
                            .proWorkFont(size: 11)
                        Text(settingsStore.localized("exchangeRates.clear", defaultValue: "Temizle"))
                            .proWorkTextStyle(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ProWorkLayout.scaled(10, using: settingsStore))
                    .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(String(format: settingsStore.localized("exchangeRates.recordCount", defaultValue: "%d kayıt"), filteredRates.count))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            HStack(alignment: .top, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
                filterColumn(label: settingsStore.localized("exchangeRates.column.currency", defaultValue: "Para Birimi")) {
                    Picker("", selection: $selectedCurrencyFilter) {
                        Text(settingsStore.localized("dateRange.all", defaultValue: "Tümü")).tag("ALL")
                        ForEach(supportedCurrencyCodes, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: ProWorkLayout.scaled(180, using: settingsStore), alignment: .leading)
                }

                filterColumn(label: settingsStore.localized("exchangeRates.column.date", defaultValue: "Tarih")) {
                    ProWorkDateRangePicker(
                        range: $filterRange,
                        customStart: $filterCustomStart,
                        customEnd: $filterCustomEnd,
                        showsAllOption: true,
                        defaultRange: .all
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore)))
    }

    private func filterColumn<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
            Text(label)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var table: some View {
        SettingsTableContainer {
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(spacing: 0) {
                    tableHeader
                    Divider()
                    ForEach(Array(filteredRates.enumerated()), id: \.element.id) { index, rate in
                        row(rate, index: index)
                        if index < filteredRates.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(width: tableContentWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(tableViewportReader)
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text(settingsStore.localized("exchangeRates.column.date", defaultValue: "Tarih")).frame(width: 140, alignment: .leading)
            Text(settingsStore.localized("exchangeRates.column.currency", defaultValue: "Para Birimi")).frame(width: 120, alignment: .leading)
            Text(settingsStore.localized("exchangeRates.column.buying", defaultValue: "Alış")).frame(width: 120, alignment: .trailing)
            Text(settingsStore.localized("exchangeRates.column.selling", defaultValue: "Satış")).frame(width: 120, alignment: .trailing)
            Text(settingsStore.localized("exchangeRates.column.cashBuying", defaultValue: "Efektif Alış")).frame(width: 140, alignment: .trailing)
            Text(settingsStore.localized("exchangeRates.column.cashSelling", defaultValue: "Efektif Satış")).frame(width: 140, alignment: .trailing)
            Text(settingsStore.localized("exchangeRates.column.source", defaultValue: "Kaynak")).frame(width: 110, alignment: .leading)
            Text(settingsStore.localized("exchangeRates.column.note", defaultValue: "Not")).frame(width: noteColumnWidth, alignment: .leading)
            Text("").frame(width: 90)
        }
        .proWorkTextStyle(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: tableContentWidth, alignment: .leading)
        .background(.quaternary.opacity(0.35))
    }

    private func row(_ rate: ExchangeRate, index: Int) -> some View {
        HStack(spacing: 12) {
            Text(formattedDate(rate.rateDate))
                .proWorkTextStyle(.callout)
                .frame(width: 140, alignment: .leading)

            Text(rate.fromCurrency)
                .proWorkTextStyle(.callout, weight: .medium)
                .frame(width: 120, alignment: .leading)

            Text(formattedRate(rate.forexBuying))
                .proWorkTextStyle(.callout)
                .frame(width: 120, alignment: .trailing)

            Text(formattedRate(rate.forexSelling))
                .proWorkTextStyle(.callout)
                .frame(width: 120, alignment: .trailing)

            Text(formattedRate(rate.banknoteBuying))
                .proWorkTextStyle(.callout)
                .frame(width: 140, alignment: .trailing)

            Text(formattedRate(rate.banknoteSelling))
                .proWorkTextStyle(.callout)
                .frame(width: 140, alignment: .trailing)

            HStack(spacing: 4) {
                Image(systemName: rate.source.systemImage)
                    .proWorkFont(size: 11)
                Text(rate.source.title)
                    .proWorkTextStyle(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(width: 110, alignment: .leading)

            Text(rate.note ?? "")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: noteColumnWidth, alignment: .leading)

            HStack(spacing: 6) {
                if rate.source == .manual {
                    Button { editingRate = rate } label: {
                        Image(systemName: "pencil").proWorkFont(size: 12)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button { askDelete(rate) } label: {
                    Image(systemName: "trash").proWorkFont(size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: tableContentWidth, alignment: .leading)
        .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.045))
    }

    private var filteredRates: [ExchangeRate] {
        rates.filter { rate in
            guard rate.source == selectedTab.source,
                  rate.toCurrency == "TRY",
                  supportedCurrencyCodes.contains(rate.fromCurrency) else {
                return false
            }

            if selectedCurrencyFilter != "ALL", rate.fromCurrency != selectedCurrencyFilter {
                return false
            }

            guard let date = Holiday.dateFormatter.date(from: rate.rateDate) else {
                return false
            }

            return filterRange.contains(
                date,
                customStart: filterCustomStart,
                customEnd: filterCustomEnd
            )
        }
        .sorted {
            if $0.rateDate != $1.rateDate {
                return $0.rateDate > $1.rateDate
            }
            return $0.fromCurrency < $1.fromCurrency
        }
    }

    private var hasActiveFilters: Bool {
        filterRange != .all || selectedCurrencyFilter != "ALL"
    }

    private func clearFilters() {
        filterRange = .all
        selectedCurrencyFilter = "ALL"
        filterCustomStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        filterCustomEnd = Date()
    }

    private func formattedDate(_ raw: String) -> String {
        guard let date = Holiday.dateFormatter.date(from: raw) else {
            return raw
        }
        return settingsStore.formatDate(date)
    }

    private func formattedRate(_ value: Decimal?) -> String {
        guard let value else { return settingsStore.localized("common.notAvailable", defaultValue: "—") }
        return rateFormatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    private func applyImportMode(_ mode: ExchangeRateImportMode) {
        importMode = mode
        guard mode == .range else { return }

        let today = Date()
        importEndDate = today
        importStartDate = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
    }

    private var tableContentWidth: CGFloat {
        fixedTableWidth + noteColumnWidth
    }

    private var noteColumnWidth: CGFloat {
        max(320, tableViewportWidth - fixedTableWidth)
    }

    private var fixedTableWidth: CGFloat {
        140 + 120 + 120 + 120 + 140 + 140 + 110 + 90 + 96 + 28
    }

    private var tableViewportReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    updateTableViewportWidth(proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    updateTableViewportWidth(newWidth)
                }
        }
    }

    private func updateTableViewportWidth(_ width: CGFloat) {
        let normalizedWidth = max(width, 0)
        guard normalizedWidth != tableViewportWidth else { return }
        tableViewportWidth = normalizedWidth
    }

    private func load() {
        do {
            rates = try repository.fetchAll(organizationId: BuiltInOrganizationId.default)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ rate: ExchangeRate) {
        do {
            try repository.upsert(rate)
            isShowingNew = false
            setSavedNotice(settingsStore.localized("exchangeRates.notice.created", defaultValue: "Manuel kur kaydedildi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func update(_ rate: ExchangeRate) {
        do {
            try repository.upsert(rate)
            editingRate = nil
            setSavedNotice(settingsStore.localized("exchangeRates.notice.updated", defaultValue: "Kur kaydı güncellendi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askDelete(_ rate: ExchangeRate) {
        confirmation = ProWorkConfirmation(
            title: settingsStore.localized("exchangeRates.delete.title", defaultValue: "Kur silinsin mi?"),
            message: String(format: settingsStore.localized("exchangeRates.delete.message", defaultValue: "%@ / TRY (%@) silinecek."), rate.fromCurrency, formattedDate(rate.rateDate)),
            confirmTitle: settingsStore.localized("exchangeRates.delete.confirm", defaultValue: "Sil"),
            cancelTitle: settingsStore.localized("exchangeRates.delete.cancel", defaultValue: "Vazgeç"),
            role: .destructive
        ) {
            delete(rate)
        }
    }

    private func delete(_ rate: ExchangeRate) {
        do {
            try repository.softDelete(id: rate.id)
            setSavedNotice(settingsStore.localized("exchangeRates.notice.deleted", defaultValue: "Kur kaydı silindi."))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importRates(from source: ExchangeRateAutoSource) {
        errorMessage = nil
        savedNotice = nil
        importingSource = source

        let startDate = importMode == .today ? Date() : importStartDate
        let endDate = importMode == .today ? Date() : importEndDate

        Task { @MainActor in
            defer { importingSource = nil }

            do {
                let result: TCMBExchangeRateSyncResult
                switch source {
                case .tcmb:
                    result = try await tcmbSyncService.sync(
                        from: startDate,
                        to: endDate,
                        currencies: supportedCurrencyCodes
                    )
                case .global:
                    result = try await globalSyncService.sync(
                        from: startDate,
                        to: endDate,
                        currencies: supportedCurrencyCodes
                    )
                }

                load()
                setSavedNotice(makeImportNotice(from: result, source: source))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func makeImportNotice(from result: TCMBExchangeRateSyncResult, source: ExchangeRateAutoSource) -> String {
        let skippedCount = result.skippedDates.count
        if skippedCount == 0 {
            return String(
                format: settingsStore.localized("exchangeRates.notice.imported", defaultValue: "%@ kaynağından %d gün için %d kayıt çekildi."),
                source.title,
                result.importedDayCount,
                result.importedRateCount
            )
        }
        return String(
            format: settingsStore.localized("exchangeRates.notice.importedWithSkips", defaultValue: "%@ kaynağından %d gün için %d kayıt çekildi, %d gün atlandı."),
            source.title,
            result.importedDayCount,
            result.importedRateCount,
            skippedCount
        )
    }

    private func setSavedNotice(_ message: String) {
        savedNotice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if savedNotice == message {
                savedNotice = nil
            }
        }
    }

    private var rateFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = settingsStore.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        return formatter
    }
}
