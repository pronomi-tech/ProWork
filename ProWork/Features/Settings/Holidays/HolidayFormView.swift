//  HolidayFormView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI
import os

enum HolidayFormMode: Hashable {
    case create
    case edit(Holiday)

    func title(using settingsStore: AppSettingsStore) -> String {
        switch self {
        case .create: return settingsStore.localized("holidays.form.mode.create", defaultValue: "Yeni Tatil")
        case .edit: return settingsStore.localized("holidays.form.mode.edit", defaultValue: "Tatili Düzenle")
        }
    }
}

struct HolidayFormView: View {
    let mode: HolidayFormMode
    let onSave: (Holiday) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @State private var date: Date = Date()
    @State private var name: String = ""
    @State private var isHalfDay: Bool = false
    @State private var halfDayCutoff: Date = TimeOfDay(hour: 13, minute: 0).combine(with: Date())
    @State private var isActive: Bool = true
    @State private var existingId: String = UUID().uuidString
    @State private var errorMessage: String?

    var body: some View {
        ProWorkFormShell(
            title: mode.title(using: settingsStore),
            subtitle: settingsStore.localized("holidays.form.subtitle", defaultValue: "Tatil günü tanımı"),
            systemImage: "calendar",
            width: FormSheetSize.holidayForm.width,
            height: FormSheetSize.holidayForm.height
        ) {
            VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(14, using: settingsStore)) {
                SettingsFormError(message: errorMessage)

                SettingsFormRow(settingsStore.localized("holidays.form.date", defaultValue: "Tarih"), required: true) {
                    ProWorkDateField(title: "", date: $date)
                        .frame(width: 220)
                }

                SettingsFormRow(settingsStore.localized("holidays.form.name", defaultValue: "Ad"), required: true) {
                    ProWorkTextField(placeholder: settingsStore.localized("holidays.form.name.placeholder", defaultValue: "Yılbaşı, Ramazan Bayramı 1. Günü..."), text: $name)
                        .frame(maxWidth: 360)
                }

                SettingsFormRow(settingsStore.localized("holidays.form.halfDay", defaultValue: "Yarım Gün")) {
                    Toggle("", isOn: $isHalfDay)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if isHalfDay {
                    SettingsFormRow(settingsStore.localized("holidays.form.cutoff", defaultValue: "Tatil Başlangıcı"), alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            ProWorkTimeField(title: "", date: $halfDayCutoff)

                            Text(settingsStore.localized("holidays.form.cutoff.help", defaultValue: "Bu saatten itibaren tatil sayılır."))
                                .proWorkTextStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsFormRow(settingsStore.localized("holidays.form.active", defaultValue: "Aktif")) {
                    Toggle("", isOn: $isActive)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Spacer(minLength: 0)
            }
        } footer: {
            SettingsFormFooter(
                onCancel: { dismiss() },
                onSave: save
            )
        }
        .onAppear { applyMode() }
    }

    private func applyMode() {
        if case .edit(let holiday) = mode {
            existingId = holiday.id
            // previously a parse failure silently left the
            // date field on its initial Date(), so a corrupt dateString in
            // the DB would let the user accidentally save "today" over the
            // intended holiday date. Log loudly so an admin can repair the
            // stored value; keep the visible date unchanged.
            if let parsed = Holiday.dateFormatter.date(from: holiday.dateString) {
                date = parsed
            } else {
                ProWorkLog.app.error(
                    "HolidayFormView.applyMode: failed to parse stored dateString \(holiday.dateString, privacy: .public) for holiday \(holiday.id, privacy: .public)"
                )
                ProWorkToastStore.shared.show(
                    settingsStore.localized(
                        "holidays.form.error.invalidStoredDate",
                        defaultValue: "Bayram tarihi okunamadı; lütfen kontrol edin."
                    ),
                    style: .warning
                )
            }
            name = holiday.name
            isHalfDay = holiday.isHalfDay
            if let cutoff = holiday.halfDayCutoff {
                halfDayCutoff = cutoff.combine(with: date)
            }
            isActive = holiday.isActive
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = settingsStore.localized("holidays.form.error.nameRequired", defaultValue: "Ad zorunludur.")
            return
        }

        let dateString = Holiday.dateFormatter.string(from: date)
        let cutoff = isHalfDay ? TimeOfDay.from(date: halfDayCutoff) : nil

        let holiday = Holiday(
            id: existingId,
            scope: .global,
            customerId: nil,
            dateString: dateString,
            name: trimmed,
            isHalfDay: isHalfDay,
            halfDayCutoff: cutoff,
            isActive: isActive,
            organizationId: BuiltInOrganizationId.default
        )

        onSave(holiday)
        dismiss()
    }
}
