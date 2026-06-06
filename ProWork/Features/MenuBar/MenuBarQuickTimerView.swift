//  MenuBarQuickTimerView.swift
//  ProWork
//   Created by Pronomi.

import SwiftUI

struct MenuBarQuickTimerView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var automationController: WorkAutomationController
    /// Subscribe to the per-second tick so the popover's
    /// `durationText` updates while open. Previously the duration was
    /// the snapshot value at panel open and would freeze until the
    /// user dismissed and reopened.
    @EnvironmentObject private var clockTicker: ProWorkClockTicker

    /// Replaces the action previously bound to the status item's
    /// double-click. Triggered by the "Main Window" button inside the popover.
    let onOpenMainWindow: () -> Void

    init(onOpenMainWindow: @escaping () -> Void = {}) {
        self.onOpenMainWindow = onOpenMainWindow
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        settingsStore.localized(key, defaultValue: defaultValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            activeSessionPanel
            pausedSessionPanel
            taskListPanel

            if let lastAutomationMessage {
                messageBanner(lastAutomationMessage)
            }
        }
        .padding(14)
        .frame(width: 430)
        .onAppear {
            // Deterministic order — settings push first, then
            // automation start. The previous code dispatched the
            // settings update inside `Task { @MainActor }` and called
            // `automationController.start()` synchronously
            // immediately after, so `start()` ran with the *old*
            // settings until the runloop picked the task up. The
            // updateSettings call is already main-actor (the
            // controller is @MainActor); call it directly so the
            // ordering is the source order.
            automationController.updateSettings(settingsStore.settings)
            automationController.start()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ProWork")
                    .proWorkTextStyle(.title3)
                    .bold()

                Text(headerSubtitle)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                headerPill(
                    title: automationController.activeSession == nil
                        ? localized("menuBar.status.ready", defaultValue: "Hazır")
                        : localized("menuBar.header.active", defaultValue: "Aktif Çalışma"),
                    color: automationController.activeSession == nil ? .secondary : .green
                )

                openMainWindowButton
                headerRefreshButton
            }
        }
    }

    private var openMainWindowButton: some View {
        Button(action: onOpenMainWindow) {
            Image(systemName: "macwindow")
                .proWorkFont(size: 13, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        // SwiftUI was giving this button default focus when the popover
        // opened and drawing an accent-coloured border around it — for
        // a single-click menu tool, keyboard focus makes no sense. The
        // other toolbar buttons are also `.focusable(false)` (e.g. the
        // confirmation-dialog actions).
        .focusable(false)
        .help(localized("menuBar.action.mainWindow", defaultValue: "Ana Ekran"))
    }

    private var taskListPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasSessionContext {
                Divider()
            }

            if displayedTodos.isEmpty {
                if hasSessionContext {
                    HStack(spacing: 8) {
                        Image(systemName: "tray")
                            .proWorkFont(size: 11)
                            .foregroundStyle(.secondary)
                        Text(localized("menuBar.empty.startable", defaultValue: "Başlatılabilir kayıt bulunmuyor."))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                } else {

                    VStack(alignment: .leading, spacing: 6) {
                        Text(emptyTaskListTitle)
                            .proWorkTextStyle(.callout, weight: .semibold)
                        Text(localized("menuBar.empty.startable", defaultValue: "Başlatılabilir kayıt bulunmuyor."))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {

                    if displayedTodos.count <= 4 {
                        VStack(spacing: 8) {
                            ForEach(displayedTodos) { todo in
                                taskRow(todo)
                            }
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(displayedTodos) { todo in
                                    taskRow(todo)
                                }
                            }
                        }
                        .frame(maxHeight: 340)
                    }
            }
        }
    }

    private func taskRow(_ todo: TodoListItem) -> some View {
        let isActive = todo.activeSessionStartedAt != nil
        let accentColor = ProWorkColors.fromName(todo.statusColor)

        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(accentColor)
                .frame(width: 5, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(todo.title)
                    .proWorkTextStyle(.callout, weight: .medium)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    inlineChip(todo.statusName, color: accentColor)

                    if let customerName = todo.customerName, !customerName.isEmpty {
                        inlineChip(customerName, color: .secondary)
                    }

                    if let dueBadge = dueBadge(for: todo) {
                        inlineChip(dueBadge.title, color: dueBadge.color)
                    }
                }

                Text(taskSubtitle(for: todo))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if isActive, let startedAt = todo.activeSessionStartedAt {
                    Text(durationSince(startedAt))
                        .proWorkTextStyle(.caption, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(.green)
                } else {
                    Text(
                        String(
                            format: localized("menuBar.totalDuration", defaultValue: "Toplam %@"),
                            ProWorkFormatters.durationHHmm(todo.totalTrackedSeconds)
                        )
                    )
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button {
                    if isActive {
                        automationController.stopWork(todoId: todo.id)
                    } else {
                        automationController.startWork(todoId: todo.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isActive ? "stop.fill" : "play.fill")
                            .proWorkFont(size: 11)
                        Text(
                            isActive
                            ? localized("menuBar.action.stop", defaultValue: "Durdur")
                            : localized("menuBar.action.start", defaultValue: "Başlat")
                        )
                            .proWorkTextStyle(.caption, weight: .semibold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(minWidth: 82)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .red : accentColor)
            }
        }
        .padding(12)
        .background(isActive ? Color.green.opacity(0.12) : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func messageBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Text(message)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if automationController.pausedSession != nil {
                Button(localized("menuBar.action.resume", defaultValue: "Devam Et")) {
                    automationController.resumePausedWork()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var activeSessionPanel: some View {
        if let active = automationController.activeSession {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(localized("menuBar.active.currentTask", defaultValue: "Şu an çalışan iş"))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)

                        Text(active.todoTitle)
                            .proWorkTextStyle(.callout, weight: .semibold)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            inlineChip(active.statusName, color: .green)
                            Text(
                                String(
                                    format: localized("menuBar.active.startedAt", defaultValue: "Başlangıç %@"),
                                    settingsStore.formatTime(active.startedAt)
                                )
                            )
                                .proWorkTextStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text(durationText(for: active))
                            .proWorkTextStyle(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.green)

                        Button {
                            automationController.stopActiveWork()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                    .proWorkFont(size: 11)
                                Text(localized("menuBar.action.stop", defaultValue: "Durdur"))
                                    .proWorkTextStyle(.caption, weight: .semibold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
            .padding(12)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var pausedSessionPanel: some View {
        if let paused = automationController.pausedSession {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 10, height: 10)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(localized("menuBar.paused.title", defaultValue: "Duraklatılmış iş"))
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)

                        Text(paused.todoTitle)
                            .proWorkTextStyle(.callout, weight: .semibold)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            inlineChip(localized("menuBar.status.paused", defaultValue: "Duraklatıldı"), color: .orange)
                            Text(
                                String(
                                    format: localized("menuBar.totalDuration", defaultValue: "Toplam %@"),
                                    durationText(for: paused)
                                )
                            )
                                .proWorkTextStyle(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Spacer(minLength: 8)

                    Button {
                        automationController.resumePausedWork()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .proWorkFont(size: 11)
                            Text(localized("menuBar.action.resume", defaultValue: "Devam Et"))
                                .proWorkTextStyle(.caption, weight: .semibold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var headerRefreshButton: some View {
        Button {
            automationController.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .proWorkFont(size: 11)
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(localized("common.refresh", defaultValue: "Yenile"))
    }

    /// Hard-coded `prefix(14)` is replaced by a named
    /// constant. The popover's content area fits 14 rows comfortably
    /// before the scroll appears; a future "show all" affordance can
    /// flip `expandedAllTodos` to bypass the cap. The cap stays
    /// inline (no extra UI today) but the constant + flag makes the
    /// expansion trivial.
    static let quickTodoVisibleLimit = 14
    @State private var expandedAllTodos = false

    private var displayedTodos: [TodoListItem] {
        let excludedTodoIds = Set([
            automationController.activeSession?.todoId,
            automationController.pausedSession?.todoId
        ].compactMap { $0 })

        let filtered = automationController.quickTodos.filter { !excludedTodoIds.contains($0.id) }
        if expandedAllTodos {
            return filtered
        }
        return Array(filtered.prefix(Self.quickTodoVisibleLimit))
    }

    private var hasSessionContext: Bool {
        automationController.activeSession != nil || automationController.pausedSession != nil
    }

    private var emptyTaskListTitle: String {
        if automationController.activeSession != nil || automationController.pausedSession != nil {
            return localized("menuBar.empty.otherTask", defaultValue: "Başka iş bulunamadı")
        }

        return localized("menuBar.empty.noSuitableTask", defaultValue: "Uygun iş bulunamadı")
    }

    private var headerSubtitle: String {
        if automationController.activeSession != nil {
            return localized("menuBar.subtitle.activeExists", defaultValue: "Aktif iş var")
        }

        if automationController.pausedSession != nil {
            return localized("menuBar.subtitle.pausedWaiting", defaultValue: "Duraklatılmış çalışma devam ettirilmeyi bekliyor")
        }

        if displayedTodos.isEmpty {
            return localized("menuBar.subtitle.noStartableTask", defaultValue: "Başlatılabilir iş yok")
        }

        return localized("menuBar.status.waiting", defaultValue: "Beklemede")
    }

    private func headerPill(title: String, color: Color) -> some View {
        Text(title)
            .proWorkTextStyle(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func inlineChip(_ title: String, color: Color) -> some View {
        Text(title)
            .proWorkTextStyle(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func dueBadge(for todo: TodoListItem) -> (title: String, color: Color)? {
        guard let referenceDate = todo.dueDate ?? todo.plannedDate else {
            return nil
        }

        // Due-date comparison anchors to Istanbul so a user
        // travelling doesn't see "due today" flip to "overdue" at the
        // wrong moment.
        let calendar = AppCalendar.istanbul
        if referenceDate < calendar.startOfDay(for: Date()) {
            return (localized("menuBar.due.overdue", defaultValue: "Gecikti"), .red)
        }
        if calendar.isDateInToday(referenceDate) {
            return (localized("menuBar.due.today", defaultValue: "Bugün"), .orange)
        }
        if calendar.isDateInTomorrow(referenceDate) {
            return (localized("menuBar.due.tomorrow", defaultValue: "Yarın"), .yellow)
        }

        return (settingsStore.formatDate(referenceDate), .secondary)
    }

    private func taskSubtitle(for todo: TodoListItem) -> String {
        let projectPart = todo.projectName ?? localized("reports.project.noProject", defaultValue: "Projesiz")
        return "\(projectPart) • \(todo.categoryName)"
    }

    private var lastAutomationMessage: String? {
        automationController.lastAutomationMessage
    }

    private func durationSince(_ startDate: Date) -> String {
        ProWorkFormatters.durationHHmm(
            max(0, Int(Date().timeIntervalSince(startDate)))
        )
    }

    /// Prefer the live elapsed time over the snapshot's
    /// captured `elapsedSeconds` so the popover ticks while open. Falls
    /// back to the snapshot value for paused sessions (where the
    /// snapshot already reflects "total tracked so far").
    private func durationText(for session: ActiveWorkSessionSummary) -> String {
        let seconds: Int
        if session.isPaused {
            seconds = session.elapsedSeconds
        } else {
            let live = Int(clockTicker.second.timeIntervalSince(session.startedAt))
            seconds = max(session.elapsedSeconds, live)
        }
        return ProWorkFormatters.durationHHmm(seconds)
    }

}
