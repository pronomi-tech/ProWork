//  ProWorkDateField.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct ProWorkDateField: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    @Binding var date: Date

    @State private var isShowingDatePicker = false

    init(
        title: String = "",
        date: Binding<Date>
    ) {
        self.title = title
        self._date = date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            if !title.isEmpty {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            dateButton
        }
    }

    private var dateButton: some View {
        Button {
            isShowingDatePicker.toggle()
        } label: {
            HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                Image(systemName: "calendar")
                    .proWorkFont(size: 15)
                    .foregroundStyle(.secondary)

                Text(settingsStore.formatDate(date))
                    .proWorkTextStyle(.callout)
                    .monospacedDigit()
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .proWorkFont(size: 11)
                    .foregroundStyle(.secondary)
            }
            .proWorkFieldContainer(
                backgroundOpacity: 0.82,
                alignment: .leading,
                fillsWidth: true,
                strokeColor: AnyShapeStyle(
                    isShowingDatePicker ? Color.accentColor : Color.secondary.opacity(0.18)
                ),
                strokeLineWidth: isShowingDatePicker ? 1.4 : 1
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingDatePicker, arrowEdge: .bottom) {
            ProWorkCalendarPicker(
                title: settingsStore.localized("dateField.selectDate", defaultValue: "Tarih Seç"),
                date: $date,
                showsTodayButton: true,
                showsConfirmButton: true
            ) {
                isShowingDatePicker = false
            }
        }
    }
}
