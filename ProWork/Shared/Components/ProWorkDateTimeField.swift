//
//  ProWorkDateTimeField.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct ProWorkDateTimeField: View {
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
        VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(6, using: settingsStore)) {
            if !title.isEmpty {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ProWorkLayout.formScaled(10, using: settingsStore)) {
                    dateButton
                        .frame(width: ProWorkLayout.formScaled(180, using: settingsStore), alignment: .leading)

                    ProWorkTimeField(
                        title: "",
                        date: $date
                    )
                    .frame(width: ProWorkLayout.formScaled(260, using: settingsStore), alignment: .leading)
                }

                VStack(alignment: .leading, spacing: ProWorkLayout.formScaled(10, using: settingsStore)) {
                    dateButton

                    ProWorkTimeField(
                        title: "",
                        date: $date
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dateButton: some View {
        Button {
            isShowingDatePicker.toggle()
        } label: {
            HStack(spacing: ProWorkLayout.formScaled(8, using: settingsStore)) {
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
            .padding(.horizontal, ProWorkLayout.formScaled(12, using: settingsStore))
            .padding(.vertical, ProWorkLayout.formScaled(6, using: settingsStore))
            .frame(
                maxWidth: .infinity,
                minHeight: ProWorkLayout.formScaled(40, using: settingsStore),
                alignment: .leading
            )
            .background(.background.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.formScaled(10, using: settingsStore)))
            .overlay(
                RoundedRectangle(cornerRadius: ProWorkLayout.formScaled(10, using: settingsStore))
                    .stroke(
                        isShowingDatePicker ? Color.accentColor : Color.secondary.opacity(0.18),
                        lineWidth: isShowingDatePicker ? 1.4 : 1
                    )
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
