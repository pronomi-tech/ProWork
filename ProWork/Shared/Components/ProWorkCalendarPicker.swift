//  ProWorkCalendarPicker.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI

struct ProWorkCalendarPicker: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    @Binding var date: Date

    let title: String
    let showsTodayButton: Bool
    let showsConfirmButton: Bool
    let onConfirm: (() -> Void)?

    @State private var visibleMonth: Date = Date()

    // Pinned to the Istanbul calendar because it's used in billing screens.
    // Otherwise the selected "day" would shift with the device TZ and
    // the period boundary would bind to the wrong DB value.
    private let calendar = AppCalendar.istanbul

    init(
        title: String? = nil,
        date: Binding<Date>,
        showsTodayButton: Bool = true,
        showsConfirmButton: Bool = true,
        onConfirm: (() -> Void)? = nil
    ) {
        self.title = title ?? ProWorkLocalizer.shared.string("calendar.title", defaultValue: "Tarih Seç")
        self._date = date
        self.showsTodayButton = showsTodayButton
        self.showsConfirmButton = showsConfirmButton
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(14, using: settingsStore)) {
            popoverHeader

            calendarHeader

            weekdayHeader

            calendarGrid

            if showsTodayButton || showsConfirmButton {
                Divider()

                footer
            }
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(390, using: settingsStore))
        .background(.background)
        .onAppear {
            visibleMonth = startOfMonth(date)
        }
        .onChange(of: date) { _, newValue in
            visibleMonth = startOfMonth(newValue)
        }
    }

    private var popoverHeader: some View {
        HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            Image(systemName: "calendar")
                .proWorkFont(size: 18, weight: .semibold)
                .foregroundStyle(.blue)

            Text(title)
                .proWorkTextStyle(.title3)

            Spacer()
        }
    }

    private var calendarHeader: some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Button {
                moveMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .proWorkFont(size: 16, weight: .semibold)
                    .frame(
                        width: ProWorkLayout.scaled(34, using: settingsStore),
                        height: ProWorkLayout.scaled(34, using: settingsStore)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(monthTitle(visibleMonth))
                .proWorkTextStyle(.headline)
                .frame(maxWidth: .infinity)

            Button {
                moveMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .proWorkFont(size: 16, weight: .semibold)
                    .frame(
                        width: ProWorkLayout.scaled(34, using: settingsStore),
                        height: ProWorkLayout.scaled(34, using: settingsStore)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ProWorkLayout.scaled(4, using: settingsStore))
    }

    private var weekdayHeader: some View {
        HStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .proWorkTextStyle(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(
                        width: dayCellSize,
                        height: ProWorkLayout.scaled(24, using: settingsStore)
                    )
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(
                    .fixed(dayCellSize),
                    spacing: ProWorkLayout.scaled(6, using: settingsStore)
                ),
                count: 7
            ),
            spacing: ProWorkLayout.scaled(6, using: settingsStore)
        ) {
            ForEach(calendarDays, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isCurrentMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: date)
        let isToday = calendar.isDateInToday(day)

        return Button {
            selectDay(day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .proWorkTextStyle(.callout, weight: isSelected ? .semibold : .regular)
                .monospacedDigit()
                .foregroundStyle(dayForegroundStyle(isCurrentMonth: isCurrentMonth, isSelected: isSelected))
                .frame(width: dayCellSize, height: dayCellSize)
                .background(
                    RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                        .fill(isSelected ? Color.accentColor.opacity(0.95) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ProWorkLayout.scaled(10, using: settingsStore))
                        .stroke(
                            isToday && !isSelected ? Color.accentColor.opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            if showsTodayButton {
                Button {
                    selectToday()
                } label: {
                    ProWorkButtonLabel(
                        title: settingsStore.localized("calendar.today", defaultValue: "Bugün"),
                        systemImage: "calendar.badge.clock",
                        minHeight: 38
                    )
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if showsConfirmButton {
                Button {
                    onConfirm?()
                } label: {
                    ProWorkButtonLabel(
                        title: settingsStore.localized("calendar.select", defaultValue: "Seç"),
                        systemImage: "checkmark",
                        minHeight: 38
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func dayForegroundStyle(
        isCurrentMonth: Bool,
        isSelected: Bool
    ) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(.white)
        }

        if isCurrentMonth {
            return AnyShapeStyle(.primary)
        }

        return AnyShapeStyle(.tertiary)
    }

    private var dayCellSize: CGFloat {
        ProWorkLayout.scaled(42, using: settingsStore)
    }

    private var weekdaySymbols: [String] {
        [
            settingsStore.localized("weekday.short.monday", defaultValue: "Pzt"),
            settingsStore.localized("weekday.short.tuesday", defaultValue: "Sal"),
            settingsStore.localized("weekday.short.wednesday", defaultValue: "Çar"),
            settingsStore.localized("weekday.short.thursday", defaultValue: "Per"),
            settingsStore.localized("weekday.short.friday", defaultValue: "Cum"),
            settingsStore.localized("weekday.short.saturday", defaultValue: "Cmt"),
            settingsStore.localized("weekday.short.sunday", defaultValue: "Paz")
        ]
    }

    private var calendarDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else {
            return []
        }

        var days: [Date] = []
        var current = firstWeekInterval.start

        while current < lastWeekInterval.end {
            days.append(current)

            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }

            current = next
        }

        return days
    }

    private func selectDay(_ selectedDay: Date) {
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: date)
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDay)

        dayComponents.hour = timeComponents.hour
        dayComponents.minute = timeComponents.minute
        dayComponents.second = timeComponents.second ?? 0

        date = calendar.date(from: dayComponents) ?? selectedDay
        visibleMonth = startOfMonth(date)
    }

    private func selectToday() {
        selectDay(Date())
        visibleMonth = startOfMonth(Date())
    }

    private func moveMonth(_ value: Int) {
        visibleMonth = calendar.date(
            byAdding: .month,
            value: value,
            to: visibleMonth
        ) ?? visibleMonth
    }

    private func startOfMonth(_ value: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: value)
        return calendar.date(from: components) ?? value
    }

    /// K16 cache adoption. Was allocating a fresh formatter
    /// per render — calendar picker re-renders on every date selection.
    private func monthTitle(_ value: Date) -> String {
        let formatter = ProWorkFormatters.cachedDateFormatter(
            localeIdentifier: settingsStore.locale.identifier,
            dateFormat: "LLLL yyyy"
        )
        return formatter.string(from: value).capitalized
    }
}
