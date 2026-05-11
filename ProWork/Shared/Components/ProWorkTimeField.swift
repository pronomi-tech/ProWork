//
//  ProWorkTimeField.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI
import AppKit

struct ProWorkTimeField: View {
    let title: String
    @Binding var date: Date

    @State private var hour: Int = 0
    @State private var minute: Int = 0
    @State private var editingUnit: EditingUnit?
    @State private var editingText: String = ""

    @FocusState private var focusedUnit: EditingUnit?

    private func localized(_ key: String, defaultValue: String) -> String {
        ProWorkLocalizer.shared.string(key, defaultValue: defaultValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                Image(systemName: "clock")
                    .foregroundStyle(.secondary)

                hourPicker

                Text(":")
                    .proWorkTextStyle(.headline)
                    .foregroundStyle(.secondary)

                minutePicker

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .proWorkFrame(minWidth: 260)
            .background(.background.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
        .onAppear {
            syncFromDate()
        }
        .onChange(of: date) { _, _ in
            syncFromDate()
        }
    }

    private var hourPicker: some View {
        HStack(spacing: 4) {
            Button {
                decrementHour()
            } label: {
                Image(systemName: "chevron.left")
                    .proWorkTextStyle(.caption2)
                    .proWorkFrame(width: 18, height: 22)
            }
            .buttonStyle(.borderless)
            .help(localized("timeField.decreaseHour", defaultValue: "1 saat azalt"))

            editableValue(
                value: hour,
                unit: .hour,
                width: 34
            )

            Button {
                incrementHour()
            } label: {
                Image(systemName: "chevron.right")
                    .proWorkTextStyle(.caption2)
                    .proWorkFrame(width: 18, height: 22)
            }
            .buttonStyle(.borderless)
            .help(localized("timeField.increaseHour", defaultValue: "1 saat artır"))
        }
    }

    private var minutePicker: some View {
        HStack(spacing: 3) {
            Button {
                decrementMinute(by: 5)
            } label: {
                Image(systemName: "chevron.left.2")
                    .proWorkTextStyle(.caption2)
                    .proWorkFrame(width: 18, height: 22)
            }
            .buttonStyle(.borderless)
            .help(localized("timeField.decreaseFiveMinutes", defaultValue: "5 dakika azalt"))

            Button {
                decrementMinute(by: 1)
            } label: {
                Image(systemName: "chevron.left")
                    .proWorkTextStyle(.caption2)
                    .proWorkFrame(width: 18, height: 22)
            }
            .buttonStyle(.borderless)
            .help(localized("timeField.decreaseMinute", defaultValue: "1 dakika azalt"))

            editableValue(
                value: minute,
                unit: .minute,
                width: 34
            )

            Button {
                incrementMinute(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .proWorkTextStyle(.caption2)
                    .proWorkFrame(width: 18, height: 22)
            }
            .buttonStyle(.borderless)
            .help(localized("timeField.increaseMinute", defaultValue: "1 dakika artır"))

            Button {
                incrementMinute(by: 5)
            } label: {
                Image(systemName: "chevron.right.2")
                    .proWorkTextStyle(.caption2)
                    .proWorkFrame(width: 18, height: 22)
            }
            .buttonStyle(.borderless)
            .help(localized("timeField.increaseFiveMinutes", defaultValue: "5 dakika artır"))
        }
    }

    private func editableValue(
        value: Int,
        unit: EditingUnit,
        width: CGFloat
    ) -> some View {
        Group {
            if editingUnit == unit {
                TextField("", text: $editingText)
                    .textFieldStyle(.plain)
                   .proWorkFont(size: 18, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .proWorkFrame(width: width)
                    .focused($focusedUnit, equals: unit)
                    .onSubmit {
                        commitEditing()
                    }
                    .onExitCommand {
                        cancelEditing()
                    }
                    .onAppear {
                        focusedUnit = unit
                        selectAllText()
                    }
            } else {
                Text(String(format: "%02d", value))
                   .proWorkFont(size: 18, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .proWorkFrame(width: width)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        beginEditing(unit, value: value)
                    }
                    .help(localized("timeField.manualEntry", defaultValue: "Çift tıklayarak elle gir"))
            }
        }
        .proWorkFrame(width: width, height: 24)
        .background(.background.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(editingUnit == unit ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }

    private func beginEditing(_ unit: EditingUnit, value: Int) {
        editingUnit = unit
        editingText = String(format: "%02d", value)

        DispatchQueue.main.async {
            focusedUnit = unit
            selectAllText()
        }
    }

    private func commitEditing() {
        guard let unit = editingUnit else {
            return
        }

        let cleanValue = editingText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rawValue = Int(cleanValue) else {
            cancelEditing()
            return
        }

        switch unit {
        case .hour:
            hour = min(23, max(0, rawValue))

        case .minute:
            minute = min(59, max(0, rawValue))
        }

        editingUnit = nil
        editingText = ""
        focusedUnit = nil

        syncToDate()
    }

    private func cancelEditing() {
        editingUnit = nil
        editingText = ""
        focusedUnit = nil
    }

    private func selectAllText() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.sendAction(
                #selector(NSText.selectAll(_:)),
                to: nil,
                from: nil
            )
        }
    }

    private func syncFromDate() {
        guard editingUnit == nil else {
            return
        }

        let calendar = Calendar.current
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }

    private func syncToDate() {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: date
        )

        components.hour = hour
        components.minute = minute
        components.second = 0

        if let newDate = Calendar.current.date(from: components) {
            date = newDate
        }
    }

    private func incrementHour() {
        hour = wrapped(hour + 1, min: 0, max: 23)
        syncToDate()
    }

    private func decrementHour() {
        hour = wrapped(hour - 1, min: 0, max: 23)
        syncToDate()
    }

    private func incrementMinute(by step: Int) {
        minute = wrapped(minute + step, min: 0, max: 59)
        syncToDate()
    }

    private func decrementMinute(by step: Int) {
        minute = wrapped(minute - step, min: 0, max: 59)
        syncToDate()
    }

    private func wrapped(
        _ value: Int,
        min: Int,
        max: Int
    ) -> Int {
        if value > max {
            return min + (value - max - 1)
        }

        if value < min {
            return max - (min - value - 1)
        }

        return value
    }
}

private enum EditingUnit: Hashable {
    case hour
    case minute
}
