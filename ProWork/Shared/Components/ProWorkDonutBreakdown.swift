//
//  ProWorkDonutBreakdown.swift
//  ProWork
//
//  Created by Pronomi.
//

import SwiftUI

struct DonutBreakdownRow: Identifiable, Hashable {
    let id: String
    let title: String
    let seconds: Int
    let color: Color
    let percentageText: String
}

struct ProWorkDonutBreakdownCard: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore

    let title: String
    let systemImage: String
    let rows: [DonutBreakdownRow]
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 15)
                    .foregroundStyle(.secondary)

                Text(title)
                    .proWorkTextStyle(.headline)

                Spacer()

                if !rows.isEmpty {
                    Text(ProWorkFormatters.durationHHmm(totalSeconds))
                        .proWorkTextStyle(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if rows.isEmpty {
                HStack {
                    Text(emptyMessage)
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(ProWorkLayout.scaled(16, using: settingsStore))
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: ProWorkLayout.scaled(18, using: settingsStore)) {
                        donutChart
                        legend
                    }

                    VStack(alignment: .leading, spacing: ProWorkLayout.scaled(18, using: settingsStore)) {
                        donutChart
                        legend
                    }
                }
            }
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var totalSeconds: Int {
        rows.reduce(0) { $0 + $1.seconds }
    }

    private var donutChart: some View {
        let segments = donutSegments

        return ZStack {
            ForEach(segments) { segment in
                DonutSliceShape(
                    startAngle: segment.startAngle,
                    endAngle: segment.endAngle,
                    innerRadiusRatio: 0.58
                )
                .fill(segment.row.color)
                .overlay {
                    DonutSliceShape(
                        startAngle: segment.startAngle,
                        endAngle: segment.endAngle,
                        innerRadiusRatio: 0.58
                    )
                    .stroke(.background, lineWidth: 2)
                }
            }

            VStack(spacing: 4) {
                Text(ProWorkFormatters.durationHHmm(totalSeconds))
                    .proWorkFont(size: 22, weight: .bold, design: .rounded)
                    .monospacedDigit()

                Text(settingsStore.localized("home.pie.total", defaultValue: "Toplam"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: ProWorkLayout.scaled(190, using: settingsStore),
            height: ProWorkLayout.scaled(190, using: settingsStore)
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            ForEach(rows) { row in
                HStack(alignment: .center, spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .proWorkTextStyle(.callout)
                            .lineLimit(1)

                        Text(ProWorkFormatters.durationHHmm(row.seconds))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)

                    Text(row.percentageText)
                        .proWorkTextStyle(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var donutSegments: [DonutSegment] {
        let total = max(totalSeconds, 1)
        var startDegrees: Double = -90

        return rows.map { row in
            let angle = (Double(row.seconds) / Double(total)) * 360
            let segment = DonutSegment(
                id: row.id,
                row: row,
                startAngle: .degrees(startDegrees),
                endAngle: .degrees(startDegrees + angle)
            )
            startDegrees += angle
            return segment
        }
    }
}

private struct DonutSegment: Identifiable {
    let id: String
    let row: DonutBreakdownRow
    let startAngle: Angle
    let endAngle: Angle
}

private struct DonutSliceShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio

        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

enum SessionBreakdownBuilder {
    struct Entry {
        let title: String
        let seconds: Int
        let colorName: String?
    }

    static func categoryRows(
        sessions: [WorkSessionListItem],
        todoLookup: [String: TodoListItem],
        unknownTitle: String,
        otherTitle: String,
        limit: Int = 5
    ) -> [DonutBreakdownRow] {
        let entries = sessions.compactMap { session -> Entry? in
            let seconds = session.durationSeconds ?? 0
            guard seconds > 0 else { return nil }
            let todo = todoLookup[session.todoId]
            let title = (todo?.categoryName.isEmpty == false ? todo?.categoryName : nil) ?? unknownTitle
            return Entry(title: title, seconds: seconds, colorName: todo?.categoryColor)
        }

        return buildRows(
            from: entries,
            otherTitle: otherTitle,
            limit: limit
        ) { entry, _ in
            ProWorkColors.fromName(entry.colorName)
        }
    }

    static func customerRows(
        sessions: [WorkSessionListItem],
        noCustomerTitle: String,
        otherTitle: String,
        limit: Int = 5
    ) -> [DonutBreakdownRow] {
        let palette = customerPalette
        let entries = sessions.compactMap { session -> Entry? in
            let seconds = session.durationSeconds ?? 0
            guard seconds > 0 else { return nil }
            let cleanTitle = session.customerName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = cleanTitle?.isEmpty == false ? cleanTitle! : noCustomerTitle
            return Entry(title: title, seconds: seconds, colorName: nil)
        }

        return buildRows(
            from: entries,
            otherTitle: otherTitle,
            limit: limit
        ) { _, index in
            palette[index % palette.count]
        }
    }

    private static func buildRows(
        from entries: [Entry],
        otherTitle: String,
        limit: Int,
        colorResolver: (Entry, Int) -> Color
    ) -> [DonutBreakdownRow] {
        guard !entries.isEmpty else { return [] }

        var aggregated: [String: Entry] = [:]
        for entry in entries {
            if let existing = aggregated[entry.title] {
                aggregated[entry.title] = Entry(
                    title: entry.title,
                    seconds: existing.seconds + entry.seconds,
                    colorName: existing.colorName ?? entry.colorName
                )
            } else {
                aggregated[entry.title] = entry
            }
        }

        var sorted = aggregated.values.sorted { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        if sorted.count > limit {
            let remainder = sorted.dropFirst(limit)
            let otherSeconds = remainder.reduce(0) { $0 + $1.seconds }
            sorted = Array(sorted.prefix(limit))
            sorted.append(Entry(title: otherTitle, seconds: otherSeconds, colorName: nil))
        }

        let total = max(sorted.reduce(0) { $0 + $1.seconds }, 1)
        return sorted.enumerated().map { index, entry in
            let percentage = Int(round((Double(entry.seconds) / Double(total)) * 100))
            return DonutBreakdownRow(
                id: entry.title,
                title: entry.title,
                seconds: entry.seconds,
                color: colorResolver(entry, index),
                percentageText: "%\(percentage)"
            )
        }
    }

    private static var customerPalette: [Color] {
        [.blue, .green, .orange, .purple, .cyan, .indigo, .mint, .pink]
    }
}
