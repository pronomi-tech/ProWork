//  BillingRulesView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct BillingRulesView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var weekdayState: [Weekday: WeekdayUIState] = BillingRulesView.defaultState()
    @State private var weekendDays: Set<Weekday> = [.saturday, .sunday]
    @State private var timezone: String = "Europe/Istanbul"
    @State private var billingWindowMode: BillingWindowMode = .timeline
    @State private var existingRule: BillingRule?
    @State private var errorMessage: String?
    @State private var savedNotice: String?
    /// Replaces the asyncAfter+string-compare
    /// pattern; race-resistant via generation counter.
    @State private var savedNoticeScheduler = NoticeScheduler()

    // Repositories are taken from AppServices so that a new instance is not
    // created every time the view struct is recreated.
    private let repository = AppServices.shared.billingRuleRepository
    private let organizationRepository = AppServices.shared.organizationRepository

    var body: some View {
        SettingsScreenScaffold(
            title: settingsStore.localized("billingRules.title", defaultValue: "Mesai Kuralları"),
            subtitle: settingsStore.localized("billingRules.subtitle", defaultValue: "Mesai içi/dışı ayrımı için her gün için çalışma saatlerini ve hafta sonu günlerini tanımlayın. Bu ayar tüm müşteriler için varsayılandır; müşteri kartından override edilebilir."),
            errorMessage: errorMessage,
            savedNotice: savedNotice,
            toolbar: {
                Button {
                    save()
                } label: {
                    ProWorkButtonLabel(title: settingsStore.localized("common.save", defaultValue: "Kaydet"), systemImage: "checkmark", minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        ) {
            billingWindowSection
            workHoursSection
            weekendSection
        }
        .onAppear { load() }
    }

    private var billingWindowSection: some View {
        SettingsCard {
            Text(settingsStore.localized("billingRules.window.title", defaultValue: "Varsayılan Minimum Pencere Akışı"))
                .proWorkTextStyle(.headline)

            Text(settingsStore.localized("billingRules.window.subtitle", defaultValue: "Projede özel seçim yoksa kullanılacak organization varsayılanını belirler."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $billingWindowMode) {
                ForEach(BillingWindowMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(billingWindowMode.subtitle)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Work hours

    private var workHoursSection: some View {
        SettingsCard {
            Text(settingsStore.localized("billingRules.hours.title", defaultValue: "Çalışma Saatleri"))
                .proWorkTextStyle(.headline)

            SettingsTableContainer {
                ForEach(Weekday.allCases) { weekday in
                    weekdayRow(weekday)
                    if weekday != .sunday {
                        Divider()
                    }
                }
            }
        }
    }

    private func weekdayRow(_ weekday: Weekday) -> some View {
        let state = bindingForWeekday(weekday)

        return HStack(alignment: .center, spacing: 16) {
            ProWorkCheckbox(weekday.title, isOn: state.isEnabled, boxSize: 22)
                .frame(width: 160, alignment: .leading)

            if state.isEnabled.wrappedValue {
                HStack(spacing: 12) {
                    ProWorkTimeField(title: "", date: state.startDate)

                    Text(settingsStore.localized("billingRules.hours.separator", defaultValue: "–"))
                        .foregroundStyle(.secondary)

                    ProWorkTimeField(title: "", date: state.endDate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            } else {
                Text(settingsStore.localized("billingRules.hours.offHours", defaultValue: "Mesai dışı"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Weekend

    private var weekendSection: some View {
        SettingsCard {
            Text(settingsStore.localized("billingRules.weekend.title", defaultValue: "Hafta Sonu Günleri"))
                .proWorkTextStyle(.headline)

            Text(settingsStore.localized("billingRules.weekend.subtitle", defaultValue: "Bu günlerdeki çalışmalar 'Hafta Sonu' zaman tipi olarak ücretlendirilir."))
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { weekday in
                    // Read `weekendDays.contains(weekday)`
                    // once per button instead of three times across
                    // the image, fill, and stroke modifiers.
                    let isWeekend = weekendDays.contains(weekday)
                    Button {
                        toggleWeekend(weekday)
                    } label: {
                        VStack(spacing: 6) {
                            Text(weekday.shortTitle)
                                .proWorkTextStyle(.callout, weight: .medium)
                            Image(systemName: isWeekend ? "checkmark.circle.fill" : "circle")
                                .proWorkFont(size: 16)
                                .foregroundStyle(isWeekend ? Color.accentColor : .secondary)
                        }
                        .frame(width: 64, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isWeekend ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isWeekend ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // MARK: - Bindings

    private struct WeekdayUIState {
        var isEnabled: Bool
        var startDate: Date
        var endDate: Date
    }

    private static func defaultState() -> [Weekday: WeekdayUIState] {
        let standardStart = TimeOfDay(hour: 9, minute: 0).combine(with: Date())
        let standardEnd = TimeOfDay(hour: 18, minute: 0).combine(with: Date())

        var state: [Weekday: WeekdayUIState] = [:]
        for weekday in Weekday.allCases {
            let isWorkDay = ![.saturday, .sunday].contains(weekday)
            state[weekday] = WeekdayUIState(
                isEnabled: isWorkDay,
                startDate: standardStart,
                endDate: standardEnd
            )
        }
        return state
    }

    private func bindingForWeekday(_ weekday: Weekday) -> (
        isEnabled: Binding<Bool>,
        startDate: Binding<Date>,
        endDate: Binding<Date>
    ) {
        (
            isEnabled: Binding(
                get: { weekdayState[weekday]?.isEnabled ?? false },
                set: { value in weekdayState[weekday]?.isEnabled = value }
            ),
            startDate: Binding(
                get: { weekdayState[weekday]?.startDate ?? Date() },
                set: { value in weekdayState[weekday]?.startDate = value }
            ),
            endDate: Binding(
                get: { weekdayState[weekday]?.endDate ?? Date() },
                set: { value in weekdayState[weekday]?.endDate = value }
            )
        )
    }

    private func toggleWeekend(_ weekday: Weekday) {
        if weekendDays.contains(weekday) {
            weekendDays.remove(weekday)
        } else {
            weekendDays.insert(weekday)
        }
    }

    // MARK: - Persistence

    private func load() {
        do {
            if let organization = try organizationRepository.fetchDefault() {
                billingWindowMode = organization.billingWindowMode
            } else {
                billingWindowMode = .timeline
            }

            if let rule = try repository.fetchGlobal(organizationId: BuiltInOrganizationId.default) {
                existingRule = rule
                applyRule(rule)
            } else {
                weekdayState = Self.defaultState()
                weekendDays = [.saturday, .sunday]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyRule(_ rule: BillingRule) {
        var state: [Weekday: WeekdayUIState] = [:]
        for weekday in Weekday.allCases {
            if let hours = rule.weekdayHours[weekday] {
                state[weekday] = WeekdayUIState(
                    isEnabled: true,
                    startDate: hours.start.combine(with: Date()),
                    endDate: hours.end.combine(with: Date())
                )
            } else {
                state[weekday] = WeekdayUIState(
                    isEnabled: false,
                    startDate: TimeOfDay(hour: 9, minute: 0).combine(with: Date()),
                    endDate: TimeOfDay(hour: 18, minute: 0).combine(with: Date())
                )
            }
        }
        weekdayState = state
        weekendDays = rule.weekendDays
        timezone = rule.timezone
    }

    private func save() {
        // Iterate weekdays in canonical order so the validation
        // error always blames the same row when multiple weekdays fail.
        // `Dictionary` has no guaranteed iteration order, so the
        // previous loop could report "Wednesday end…" on one run
        // and "Monday end…" on the next for the same inputs.
        var hours: [Weekday: DailyWorkHours] = [:]
        for weekday in Weekday.allCases {
            guard let state = weekdayState[weekday], state.isEnabled else { continue }
            let start = TimeOfDay.from(date: state.startDate)
            let end = TimeOfDay.from(date: state.endDate)
            guard end > start else {
                errorMessage = String(format: settingsStore.localized("billingRules.error.invalidHours", defaultValue: "%@ için bitiş başlangıçtan sonra olmalı."), weekday.title)
                return
            }
            hours[weekday] = DailyWorkHours(start: start, end: end)
        }

        let rule = BillingRule(
            id: existingRule?.id ?? UUID().uuidString,
            scope: .global,
            customerId: nil,
            weekdayHours: hours,
            weekendDays: weekendDays,
            timezone: timezone,
            isActive: true,
            organizationId: BuiltInOrganizationId.default,
            createdAt: existingRule?.createdAt ?? Date()
        )

        // Organization update + rule upsert must be atomic.
        // Without the transaction a successful org update followed by
        // a failed rule upsert leaves the org's billingWindowMode
        // changed while the rule write rolls back at the user's eye,
        // so refreshing the page would show inconsistent state.
        do {
            try AppDatabase.shared.inWriteTransaction {
                if var organization = try organizationRepository.fetchDefault() {
                    organization.billingWindowMode = billingWindowMode
                    try organizationRepository.update(organization)
                }
                try repository.upsert(rule)
            }
            existingRule = rule
            errorMessage = nil
            savedNoticeScheduler.show(
                settingsStore.localized("common.saved", defaultValue: "Kaydedildi.")
            ) { value in
                savedNotice = value
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
