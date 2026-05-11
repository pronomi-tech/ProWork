//
//  ProWorkDateRangePicker.swift
//  ProWork
//
//  Created by Pronomi.
//
//  WorkSessionsView ve Reports ekranlarında ortak tarih aralığı seçici.
//  - Bugün / Dün / Bu Hafta / Bu Ay quick chip'leri
//  - "Geçmiş" menü (1–6 ay)
//  - "Özel" popover (başlangıç + bitiş)
//
//  Caller `range`, `customStart`, `customEnd` binding'lerini taşır.
//  `showsAllOption` ile "Tümü" eklenip eklenmeyeceği belirlenir.
//

import SwiftUI

struct ProWorkDateRangePicker: View {
    @Binding var range: DateRangeFilter
    @Binding var customStart: Date
    @Binding var customEnd: Date

    var showsAllOption: Bool = false
    var pastMonthsRange: ClosedRange<Int> = 1...6
    var defaultRange: DateRangeFilter? = nil

    @State private var isShowingCustomPopover = false
    @EnvironmentObject private var settingsStore: AppSettingsStore

    var body: some View {
        HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            if showsAllOption {
                chipButton(settingsStore.localized("dateRange.all", defaultValue: "Tümü"), value: .all)
            }
            chipButton(settingsStore.localized("dateRange.today", defaultValue: "Bugün"), value: .today)
            chipButton(settingsStore.localized("dateRange.yesterday", defaultValue: "Dün"), value: .yesterday)
            chipButton(settingsStore.localized("dateRange.thisWeek", defaultValue: "Bu Hafta"), value: .thisWeek)
            chipButton(settingsStore.localized("dateRange.thisMonth", defaultValue: "Bu Ay"), value: .thisMonth)
            pastMonthsMenu
            customRangeButton
        }
        .onChange(of: customStart) { _, newValue in
            if newValue > customEnd {
                customEnd = newValue
            }
        }
        .onChange(of: customEnd) { _, newValue in
            if newValue < customStart {
                customStart = newValue
            }
        }
    }

    // MARK: - Chip

    private func chipButton(_ title: String, value: DateRangeFilter) -> some View {
        let isActive = range == value
        return Button {
            if isActive, let defaultRange {
                range = defaultRange
            } else {
                range = value
            }
        } label: {
            Text(title)
                .proWorkTextStyle(.caption, weight: isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .padding(.horizontal, ProWorkLayout.scaled(10, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                .background(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Past months

    private var pastMonthsMenu: some View {
        let isActive: Bool = {
            if case .pastMonths = range { return true }
            return false
        }()
        let label: String = {
            if case .pastMonths(let n) = range {
                return String(format: settingsStore.localized("dateRange.pastMonths", defaultValue: "Son %d Ay"), n)
            }
            return settingsStore.localized("dateRange.past", defaultValue: "Geçmiş")
        }()

        return Menu {
            ForEach(Array(pastMonthsRange), id: \.self) { n in
                Button(String(format: settingsStore.localized("dateRange.pastMonths", defaultValue: "Son %d Ay"), n)) {
                    range = .pastMonths(n)
                }
            }
        } label: {
            HStack(spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(label)
                    .proWorkTextStyle(.caption, weight: isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                Image(systemName: "chevron.down")
                    .proWorkFont(size: 9)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, ProWorkLayout.scaled(10, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // MARK: - Custom

    private var customRangeButton: some View {
        let isActive = range == .custom
        return Button {
            range = .custom
            isShowingCustomPopover = true
        } label: {
            Text(isActive ? customRangeLabel : settingsStore.localized("dateRange.custom", defaultValue: "Özel"))
                .proWorkTextStyle(.caption, weight: isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .padding(.horizontal, ProWorkLayout.scaled(10, using: settingsStore))
                .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
                .background(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(8, using: settingsStore)))
        }
        .buttonStyle(.plain)
        .help(isActive ? customRangeTooltip : settingsStore.localized("dateRange.custom.help", defaultValue: "Özel tarih aralığı seç"))
        .popover(isPresented: $isShowingCustomPopover, arrowEdge: .bottom) {
            customDatePopoverContent
        }
    }

    private var customRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        fmt.locale = settingsStore.locale
        return "\(fmt.string(from: customStart)) – \(fmt.string(from: customEnd))"
    }

    private var customRangeTooltip: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.locale = settingsStore.locale
        return "\(fmt.string(from: customStart)) – \(fmt.string(from: customEnd))"
    }

    private var customDatePopoverContent: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            Text(settingsStore.localized("dateRange.popover.title", defaultValue: "Tarih Aralığı"))
                .proWorkTextStyle(.headline)

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("dateRange.start", defaultValue: "Başlangıç"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                ProWorkDateField(title: "", date: $customStart)
            }

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(settingsStore.localized("dateRange.end", defaultValue: "Bitiş"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                ProWorkDateField(title: "", date: $customEnd)
            }

            Button {
                isShowingCustomPopover = false
            } label: {
                ProWorkButtonLabel(title: settingsStore.localized("dateRange.apply", defaultValue: "Uygula"), systemImage: "checkmark", minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(ProWorkLayout.scaled(20, using: settingsStore))
        .frame(width: 300)
    }
}
