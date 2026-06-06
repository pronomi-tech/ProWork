//  TodoBoardCardView.swift
//  ProWork
//  Created by Pronomi.

import SwiftUI
import Combine

struct TodoBoardCardView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var clockTicker: ProWorkClockTicker

    let todo: TodoListItem
    let onEdit: () -> Void
    let onShowSessions: () -> Void
    let onStartWork: () -> Void
    let onStopWork: () -> Void
    let onDelete: () -> Void

    // Read `clockTicker.halfMinute` directly
    // instead of mirroring it into a `@State now`. The mirror added a
    // second source of truth and forced every onReceive tick to mutate
    // state on *idle* cards too. Reading the published value gives us
    // automatic dependency tracking: only running cards (the ones that
    // actually display elapsed seconds) participate in the redraw.
    @State private var isShowingActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            header

            Text(todo.title)
                .proWorkTextStyle(.headline)
                .lineLimit(2)

            Text(subtitle)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let description = todo.description, !description.isEmpty {
                Text(description)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            footer
        }
        .padding(ProWorkLayout.scaled(12, using: settingsStore))
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                .stroke(
                    isRunning ? ProWorkColors.activeHighlightBorder : Color.secondary.opacity(0.16),
                    lineWidth: isRunning ? 2 : 1
                )
        )
        .shadow(
            color: isRunning ? ProWorkColors.activeHighlight.opacity(0.18) : .clear,
            radius: isRunning ? 12 : 0,
            y: isRunning ? 4 : 0
        )
    }

    private var header: some View {
        HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            Circle()
                .fill(ProWorkColors.fromName(todo.categoryColor))
                .frame(
                    width: ProWorkLayout.scaled(9, using: settingsStore),
                    height: ProWorkLayout.scaled(9, using: settingsStore)
                )

            Text(todo.categoryName)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if isRunning {
                activeBadge
            }

            Spacer()

            quickWorkButton

            actionsButton
        }
    }

    private var activeBadge: some View {
        Text(settingsStore.localized("workSessions.status.active", defaultValue: "Aktif"))
            .proWorkTextStyle(.caption2)
            .foregroundStyle(ProWorkColors.activeHighlight)
            .padding(.horizontal, ProWorkLayout.scaled(7, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(3, using: settingsStore))
            .background(ProWorkColors.activeHighlightFill)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var quickWorkButton: some View {
        if isRunning {
            iconButton(
                systemImage: "stop.circle.fill",
                help: settingsStore.localized("workSessions.action.stop", defaultValue: "Çalışmayı durdur"),
                foregroundStyle: AnyShapeStyle(ProWorkColors.stopAction)
            ) {
                onStopWork()
            }
        } else if todo.statusStartsTimer {
            iconButton(
                systemImage: "play.circle.fill",
                help: settingsStore.localized("workSessions.action.start", defaultValue: "Çalışmayı başlat"),
                foregroundStyle: AnyShapeStyle(ProWorkColors.startAction)
            ) {
                onStartWork()
            }
        }
    }

    private var actionsButton: some View {
        Button {
            isShowingActions.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .proWorkFont(size: 18, weight: .semibold)
                .frame(
                    width: ProWorkLayout.scaled(30, using: settingsStore),
                    height: ProWorkLayout.scaled(30, using: settingsStore)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(settingsStore.localized("todos.action.actions", defaultValue: "İşlemler"))
        .popover(isPresented: $isShowingActions, arrowEdge: .bottom) {
            actionsPopover
        }
    }

    private var actionsPopover: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            actionRow(
                title: settingsStore.localized("customers.action.edit", defaultValue: "Düzenle"),
                systemImage: "pencil"
            ) {
                isShowingActions = false
                onEdit()
            }

            actionRow(
                title: settingsStore.localized("todoSessions.title", defaultValue: "Çalışmalar"),
                systemImage: "clock"
            ) {
                isShowingActions = false
                onShowSessions()
            }

            Divider()
                .padding(.vertical, ProWorkLayout.scaled(2, using: settingsStore))

            actionRow(
                title: settingsStore.localized("todos.delete.confirm", defaultValue: "Sil"),
                systemImage: "trash",
                isDestructive: true
            ) {
                isShowingActions = false
                onDelete()
            }
        }
        .padding(ProWorkLayout.scaled(10, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(190, using: settingsStore))
    }

    private func actionRow(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 15, weight: .semibold)
                    .frame(width: ProWorkLayout.scaled(20, using: settingsStore))

                Text(title)
                    .proWorkTextStyle(.callout, weight: .medium)

                Spacer()
            }
            .foregroundStyle(isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .padding(.horizontal, ProWorkLayout.scaled(10, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(8, using: settingsStore))
            .frame(
                maxWidth: .infinity,
                minHeight: ProWorkLayout.scaled(38, using: settingsStore),
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: ProWorkLayout.scaled(9, using: settingsStore))
                    .fill(Color.secondary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        systemImage: String,
        help: String,
        foregroundStyle: AnyShapeStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .proWorkFont(size: 19)
                .foregroundStyle(foregroundStyle)
                .frame(
                    width: ProWorkLayout.scaled(30, using: settingsStore),
                    height: ProWorkLayout.scaled(30, using: settingsStore)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var footer: some View {
        HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
            Text(ProWorkLabels.priorityTitle(todo.priority))
                .proWorkTextStyle(.caption2)
                .foregroundStyle(ProWorkLabels.priorityColor(todo.priority))

            if todo.isBillable {
                Text(settingsStore.localized("todos.billable", defaultValue: "Faturalandırılır"))
                    .proWorkTextStyle(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text(settingsStore.localized("todos.administrative", defaultValue: "İdari"))
                    .proWorkTextStyle(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isRunning {
                Text(settingsStore.localized("todos.running", defaultValue: "Çalışıyor"))
                    .proWorkTextStyle(.caption2)
                    .foregroundStyle(ProWorkColors.activeHighlight)
            }

            Spacer()

            if displayedTrackedSeconds > 0 || isRunning {
                Text(ProWorkFormatters.durationHHmm(displayedTrackedSeconds))
                    .proWorkTextStyle(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(isRunning ? ProWorkColors.activeHighlight : .secondary)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []

        if let customerName = todo.customerName, !customerName.isEmpty {
            parts.append(customerName)
        } else {
            parts.append(settingsStore.localized("todos.administrative", defaultValue: "İdari"))
        }

        if let projectName = todo.projectName, !projectName.isEmpty {
            parts.append(projectName)
        }

        if let estimatedMinutes = todo.estimatedMinutes {
            parts.append(String(format: settingsStore.localized("todos.duration.minutes", defaultValue: "%d dk"), estimatedMinutes))
        }

        return parts.joined(separator: " • ")
    }

    private var isRunning: Bool {
        todo.activeSessionStartedAt != nil
    }

    private var displayedTrackedSeconds: Int {
        guard let activeSessionStartedAt = todo.activeSessionStartedAt else {
            return todo.totalTrackedSeconds
        }

        // Reading `clockTicker.halfMinute` here gives SwiftUI a
        // dependency on the ticker, so only running cards re-render.
        let activeSeconds = max(
            0,
            Int(clockTicker.halfMinute.timeIntervalSince(activeSessionStartedAt))
        )

        return todo.totalTrackedSeconds + activeSeconds
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isRunning {
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ProWorkColors.activeHighlightFill,
                                ProWorkColors.activeHighlightSurface,
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        } else {
            Rectangle()
                .fill(.regularMaterial)
        }
    }
}
