//  BillingRunCreateSheet.swift
//  ProWork
//  Extracted from BillingRunsView: the host view was
//  1746 lines; the sheet body was ~560 of those and had no shared state
//  with the parent view beyond the typed `onSave` callback. Moving the
//  sheet to its own file leaves BillingRunsView focused on the
//  list / detail orchestration and lets this file evolve on its own
//  review cycle.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BillingRunCreateSheet: View {
    let customers: [Customer]
    let customerCurrencies: [String: String]
    let onSave: (String, Date, Date, String?, [String]) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @StateObject private var viewModel = BillingDraftPickerViewModel()

    @State private var selectedCustomerId: String = ""
    @State private var selectedLineKeys: Set<String> = []
    @State private var title: String = ""
    @State private var range: DateRangeFilter = .thisMonth
    @State private var customStart: Date = AppCalendar.istanbul.date(from: AppCalendar.istanbul.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var customEnd: Date = Date()

    // ViewModel proxy — the sheet body uses these names in 30+ places.
    //
    // The `nonmutating set` proxies below are intentional but
    // brittle. SwiftUI value-type Views can't expose a setter that
    // mutates `@State` indirectly without `nonmutating set`, and the
    // backing store sits on the `viewModel` (a reference type), so the
    // pattern works today. **DO NOT** copy this onto a value-typed
    // backing store — it would silently store into a temporary copy.
    // If the proxy ever needs to write to a `@State` private var,
    // switch the field to `@StateObject` first.
    private var availableCustomers: [Customer] { viewModel.availableCustomers }
    private var availableCustomerCurrencies: [String: String] { viewModel.availableCustomerCurrencies }
    private var preview: BillingDraftPreview? { viewModel.preview }
    private var isLoadingPreview: Bool { viewModel.isLoadingPreview }
    private var isImportingTodayRates: Bool { viewModel.isImportingTodayRates }
    private var previewErrorMessage: String? {
        get { viewModel.previewErrorMessage }
        nonmutating set { viewModel.previewErrorMessage = newValue }
    }
    private var previewNoticeMessage: String? {
        get { viewModel.previewNoticeMessage }
        nonmutating set { viewModel.previewNoticeMessage = newValue }
    }
    private var lifecycleService: BillingRunLifecycleService { viewModel.lifecycleService }

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            ProWorkFormHeader(
                title: localized("billing.create.title", defaultValue: "Yeni Hizmet Dökümü Taslağı"),
                subtitle: localized("billing.create.subtitle", defaultValue: "Müşteri ve dönem seçin, ardından gönderilecek hizmet satırlarını işaretleyin."),
                systemImage: "doc.text.magnifyingglass"
            )

            formFields

            Divider()

            footer
        }
        .padding(ProWorkLayout.formScaled(24, using: settingsStore))
        .frame(
            width: ProWorkLayout.formScaled(980, using: settingsStore),
            height: ProWorkLayout.formScaled(860, using: settingsStore),
            alignment: .topLeading
        )
        .onAppear {
            loadCustomers()
        }
        .onChange(of: selectedCustomerId) { _, _ in loadPreview() }
        .onChange(of: range) { _, _ in loadPreview() }
        .onChange(of: customStart) { _, _ in loadPreview() }
        .onChange(of: customEnd) { _, _ in loadPreview() }
        // `viewModel.loadPreview(...)` is debounced 300 ms;
        // reading `viewModel.preview` synchronously right after the
        // call always saw nil and cleared `selectedLineKeys`, so the
        // "all-selected on open" UX never fired. Observing the
        // published preview here closes the race — when the debounced
        // load lands we auto-select every available line.
        .onChange(of: viewModel.preview) { _, newPreview in
            if let newPreview {
                selectedLineKeys = Set(newPreview.availableLines.map(\.selectionKey))
            } else {
                selectedLineKeys.removeAll()
            }
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(18, using: settingsStore)) {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                formRow(label: localized("projects.form.customer", defaultValue: "Müşteri")) {
                    ProWorkSearchPickerField(
                        placeholder: localized("billing.create.customerPlaceholder", defaultValue: "Müşteri seçin"),
                        items: availableCustomers,
                        selectedId: $selectedCustomerId,
                        isDisabled: availableCustomers.isEmpty,
                        showsSearch: availableCustomers.count > 8,
                        systemImage: "person.2",
                        itemTitle: { $0.name },
                        itemSubtitle: { availableCustomerCurrencies[$0.id] ?? "TRY" },
                        matchesSearch: { item, text in
                            item.name.localizedCaseInsensitiveContains(text)
                        }
                    )
                    .frame(width: ProWorkLayout.formScaled(360, using: settingsStore))
                }

                formRow(label: localized("billing.create.runTitle", defaultValue: "Döküm Başlığı")) {
                    ProWorkTextField(
                        placeholder: "",
                        text: $title,
                        minHeight: 40
                    )
                    .frame(width: ProWorkLayout.formScaled(420, using: settingsStore))
                }

                formRow(label: localized("reports.filter.period", defaultValue: "Dönem"), alignment: .top) {
                    ProWorkDateRangePicker(
                        range: $range,
                        customStart: $customStart,
                        customEnd: $customEnd,
                        defaultRange: .thisMonth
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            previewSection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var footer: some View {
        ProWorkFormFooter(
            onCancel: { dismiss() },
            onSave: { saveDraft() },
            saveTitle: localized("common.create", defaultValue: "Oluştur"),
            saveDisabled: selectedCustomerId.isEmpty || selectedLineKeys.isEmpty || isLoadingPreview
        )
    }

    @ViewBuilder
    private var previewSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(12, using: settingsStore)) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("billing.previewSelection.title", defaultValue: "Satır Seçimi"))
                            .proWorkTextStyle(.headline)
                        Text(localized("billing.previewSelection.subtitle", defaultValue: "Aynı hesap satırı birden fazla hizmet dökümünde kullanılamaz. Kilitli satırlar görünür ama seçilemez."))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLoadingPreview {
                        ProgressView()
                            .controlSize(.small)
                    } else if !selectablePreviewLines.isEmpty {
                        HStack(spacing: 10) {
                            Button(localized("common.selectAll", defaultValue: "Tümünü Seç")) {
                                selectedLineKeys = Set(selectablePreviewLines.map(\.selectionKey))
                            }
                            .buttonStyle(.borderless)

                            Button(localized("common.clear", defaultValue: "Temizle")) {
                                selectedLineKeys.removeAll()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                ProWorkFormError(message: previewErrorMessage)
                Color.clear
                    .frame(height: 0)
                    .proWorkToastNotifications(successMessage: previewNoticeMessage)

                if let preview {
                HStack(spacing: 18) {
                    previewMetric(localized("billing.previewMetric.available", defaultValue: "Uygun Satır"), "\(preview.availableLines.count)")
                    previewMetric(localized("billing.previewMetric.blocked", defaultValue: "Engelli Satır"), "\(preview.blockedLineCount)")
                    previewMetric(localized("billing.previewMetric.selected", defaultValue: "Seçilen"), "\(selectedLineKeys.count)")
                    previewMetric(localized("billing.previewMetric.drafts", defaultValue: "Taslak"), "\(selectedDraftCount)")
                    previewMetric(localized("billing.previewMetric.selectedAmount", defaultValue: "Seçili Tutar"), selectedTotalsDisplay)
                    masterTotalMetric
                    Spacer()
                }

                if selectedDraftCount > 1 {
                    Text(String(format: localized("billing.previewSelection.multipleCurrencies", defaultValue: "Seçili satırlar %d farklı para birimine dağılıyor. Oluşturma işleminde her para birimi için ayrı hizmet dökümü taslağı açılacak."), selectedDraftCount))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }

                if preview.lines.isEmpty {
                    SettingsEmptyState(
                            systemImage: "list.bullet.clipboard",
                            title: localized("billing.previewSelection.empty.title", defaultValue: "Satır bulunamadı"),
                            message: localized("billing.previewSelection.empty.message", defaultValue: "Seçilen dönem için hesaplanabilir hizmet satırı bulunamadı.")
                        )
                    } else {
                        ScrollView(.horizontal) {
                            previewTable(preview.lines)
                        }
                    }
                } else if isLoadingPreview {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(localized("billing.previewSelection.loading", defaultValue: "Hizmet satırları hazırlanıyor..."))
                            .proWorkTextStyle(.callout)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private func previewTable(_ lines: [BillingDraftPreviewLine]) -> some View {
        SettingsTableContainer {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Color.clear.frame(width: 36)
                    Text(localized("reports.todo.table.todo", defaultValue: "Görev")).frame(width: 260, alignment: .leading)
                    Text(localized("projects.title.single", defaultValue: "Proje")).frame(width: 150, alignment: .leading)
                    Text(localized("priceLists.rows.form.serviceType", defaultValue: "Hizmet")).frame(width: 90, alignment: .leading)
                    Text(localized("priceLists.rows.form.timeType", defaultValue: "Zaman")).frame(width: 100, alignment: .leading)
                    Text(localized("workSessions.column.start", defaultValue: "Başlangıç")).frame(width: 150, alignment: .leading)
                    Text(localized("reports.table.billable", defaultValue: "Ücretli")).frame(width: 70, alignment: .trailing)
                    Text(localized("reports.table.amount", defaultValue: "Tutar")).frame(width: 130, alignment: .trailing)
                    Text(localized("projects.form.status", defaultValue: "Durum")).frame(width: 180, alignment: .leading)
                }
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.35))

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(lines) { line in
                            previewRow(line)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1210, maxHeight: .infinity, alignment: .leading)
    }

    private func previewRow(_ previewLine: BillingDraftPreviewLine) -> some View {
        let line = previewLine.line
        let isOpenSession = line.endedAt == nil

        return HStack(spacing: 12) {
            ProWorkCheckbox(
                isOn: selectionBinding(for: previewLine.selectionKey),
                isDisabled: !previewLine.isSelectable,
                boxSize: 20
            )
            .frame(width: 36, alignment: .leading)

            Text(line.todoTitle)
                .proWorkTextStyle(.callout)
                .frame(width: 260, alignment: .leading)
                .lineLimit(1)
            Text(line.projectName ?? "—")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)
            Text(line.isFixedFee ? localized("export.column.fixedFee", defaultValue: "Sabit") : line.serviceType.title)
                .proWorkTextStyle(.caption)
                .frame(width: 90, alignment: .leading)
            Text(line.isFixedFee ? "—" : line.timeType.title)
                .proWorkTextStyle(.caption)
                .frame(width: 100, alignment: .leading)
            Text(line.startedAt.map(settingsStore.formatDateTime) ?? "—")
                .proWorkTextStyle(.caption)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)
            Text(
                isOpenSession
                ? "—"
                : (
                    line.isFixedFee
                    ? String(format: localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), 0)
                    : String(format: localized("workSessions.form.duration.minutes", defaultValue: "%d dk"), line.billableMinutes)
                )
            )
                .proWorkTextStyle(.caption)
                .frame(width: 70, alignment: .trailing)
            Text(isOpenSession ? "—" : ProWorkFormatters.money(line.total))
                .proWorkTextStyle(.caption, weight: .medium)
                .frame(width: 130, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.isManual
                     ? localized("workSessions.source.manual", defaultValue: "Manuel")
                     : localized("workSessions.source.automatic", defaultValue: "Otomatik"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(line.isManual ? .orange : .secondary)

                if let blockingRunLabel = previewLine.blockingRunLabel {
                    Text("\(localized("billing.previewSelection.locked", defaultValue: "Kilitli")): \(blockingRunLabel)")
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .frame(width: 180, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(previewLine.isSelectable ? 1 : 0.6)
    }

    private func formRow<Content: View>(
        label: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: ProWorkLayout.formScaled(16, using: settingsStore)) {
            Text(label)
                .proWorkTextStyle(.callout, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: ProWorkLayout.formScaled(170, using: settingsStore), alignment: .leading)

            HStack {
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .proWorkTextStyle(.callout, weight: .medium)
        }
    }

    @ViewBuilder
    private var masterTotalMetric: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("billing.previewMetric.masterCurrency", defaultValue: "Ana Para Birimi"))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)

            switch selectedTotalInMasterState {
            case .ready(let value):
                Text(value)
                    .proWorkTextStyle(.callout, weight: .medium)
            case .missingRate:
                Button {
                    importTodayRatesForPreview()
                } label: {
                    HStack(spacing: 6) {
                        if isImportingTodayRates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: settingsStore.settings.preferredExchangeRateSource.systemImage)
                                .proWorkFont(size: 12)
                        }
                        Text(
                            isImportingTodayRates
                            ? localized("billing.previewMetric.fetchingRates", defaultValue: "Çekiliyor...")
                            : localized("billing.previewMetric.rateMissing", defaultValue: "Kur eksik")
                        )
                            .proWorkTextStyle(.callout, weight: .medium)
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .disabled(isImportingTodayRates)
                .help(localized("billing.previewMetric.fetchRatesHelp", defaultValue: "Bugün için varsayılan kur kaynağını çek, gerekirse fallback kaynağı dene"))
            }
        }
    }

    private func selectionBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedLineKeys.contains(key) },
            set: { isSelected in
                if isSelected {
                    selectedLineKeys.insert(key)
                } else {
                    selectedLineKeys.remove(key)
                }
            }
        )
    }

    private func saveDraft() {
        do {
            try onSave(
                selectedCustomerId,
                effectiveStartDate,
                inclusiveEndDate,
                title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                Array(selectedLineKeys)
            )
            dismiss()
        } catch {
            previewErrorMessage = error.localizedDescription
        }
    }

    private func loadPreview() {
        guard !selectedCustomerId.isEmpty else {
            viewModel.clearPreview()
            selectedLineKeys.removeAll()
            return
        }

        viewModel.loadPreview(
            customerId: selectedCustomerId,
            periodStart: effectiveStartDate,
            periodEnd: inclusiveEndDate
        )

        if let loaded = viewModel.preview {
            selectedLineKeys = Set(loaded.availableLines.map(\.selectionKey))
        } else {
            selectedLineKeys.removeAll()
        }
    }

    private var selectablePreviewLines: [BillingDraftPreviewLine] {
        preview?.availableLines ?? []
    }

    private var selectedLineMonies: [Money] {
        selectablePreviewLines
            .filter { selectedLineKeys.contains($0.selectionKey) }
            .map { Money(minorUnits: $0.line.totalMinor, currency: $0.line.currency) }
    }

    private var selectedDraftCount: Int {
        Set(
            selectablePreviewLines
                .filter { selectedLineKeys.contains($0.selectionKey) }
                .map(\.line.currency)
        ).count
    }

    private var selectedTotalsDisplay: String {
        let grouped = Dictionary(grouping: selectedLineMonies, by: \.currency)
        let parts = grouped.keys.sorted().compactMap { currency -> String? in
            guard let monies = grouped[currency] else { return nil }
            let totalMinor = monies.reduce(0) { $0 + $1.minorUnits }
            return ProWorkFormatters.money(Money(minorUnits: totalMinor, currency: currency))
        }

        if parts.isEmpty {
            return ProWorkFormatters.money(Money.zero(availableCustomerCurrencies[selectedCustomerId] ?? "TRY"))
        }

        return parts.joined(separator: " + ")
    }

    private func loadCustomers() {
        viewModel.loadCustomers(fallback: customers, fallbackCurrencies: customerCurrencies)

        let loaded = viewModel.availableCustomers
        let availableIds = Set(loaded.map(\.id))
        if selectedCustomerId.isEmpty || !availableIds.contains(selectedCustomerId) {
            selectedCustomerId = loaded.first?.id ?? ""
        } else {
            loadPreview()
        }

        if loaded.isEmpty {
            viewModel.clearPreview()
            selectedLineKeys.removeAll()
        }
    }

    private var selectedTotalInMasterState: MasterTotalState {
        let masterCurrency = viewModel.masterCurrency()
        guard !selectedLineMonies.isEmpty else {
            return .ready(ProWorkFormatters.money(Money.zero(masterCurrency)))
        }

        let converter = CurrencyConverter(
            organizationId: BuiltInOrganizationId.default,
            masterCurrency: masterCurrency,
            preferredAutoSource: settingsStore.settings.preferredExchangeRateSource
        )

        do {
            let total = try converter.sumInMaster(
                selectedLineMonies,
                on: Self.dayFormatter.string(from: inclusiveEndDate)
            )
            return .ready(ProWorkFormatters.money(total))
        } catch {
            return .missingRate
        }
    }

    private func importTodayRatesForPreview() {
        let preferredSource = settingsStore.settings.preferredExchangeRateSource
        let currencies = previewRequiredCurrencyCodes

        Task { @MainActor in
            if let outcome = await viewModel.importTodayRates(
                currencies: currencies,
                preferredSource: preferredSource
            ) {
                loadPreview()
                viewModel.previewNoticeMessage = makeTodayRateNotice(from: outcome.result, source: outcome.source)
            }
        }
    }

    private func makeTodayRateNotice(
        from result: TCMBExchangeRateSyncResult,
        source: ExchangeRateAutoSource
    ) -> String {
        if result.importedDayCount > 0 {
            return String(
                format: localized("billing.notice.ratesImported", defaultValue: "Bugün için %d adet %@ kur kaydı çekildi."),
                result.importedRateCount,
                source.title
            )
        }
        return String(
            format: localized("billing.notice.ratesUnavailable", defaultValue: "Bugün için %@ kuru yayımlanmadı."),
            source.title
        )
    }

    private var previewRequiredCurrencyCodes: [String] {
        let masterCurrency = viewModel.masterCurrency()
        var currencies = Set(
            selectedLineMonies
                .map(\.currency)
                .map { $0.uppercased() }
        )
        currencies.insert(masterCurrency)
        currencies.remove("TRY")
        return currencies.sorted()
    }

    private var effectiveStartDate: Date {
        range.startDate(custom: customStart)
    }

    private var inclusiveEndDate: Date {
        if range == .custom {
            return customEnd
        }

        let exclusive = range.endDate(custom: customEnd)
        return AppCalendar.istanbul.date(byAdding: .day, value: -1, to: exclusive) ?? customEnd
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private enum MasterTotalState {
        case ready(String)
        case missingRate
    }

    // CompositeRateImportError was moved to BillingDraftPickerViewModel.swift.
}

// String helper used by saveDraft; kept fileprivate so the per-file
// duplicates elsewhere in the project (M10 follow-up DRY candidate)
// don't shadow each other.