//  HomeView.swift
//  ProWork
//  Created by Pronomi.
//  Home page: an overview focused on daily work. Active timer, today's
//  summary, overdue and in-progress items, recent sessions and the
//  weekly chart.

import Combine
import SwiftUI

enum HomeNavigationTarget {
    case todos
    case workSessions
    case billing
    case reports
    case definitions
}

struct HomeView: View {
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var automationController: WorkAutomationController

    var onNavigate: (HomeNavigationTarget) -> Void = { _ in }

    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var clockTicker: ProWorkClockTicker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                header

                if let active = automationController.activeSession {
                    sessionCard(active, isPaused: false)
                } else if let paused = automationController.pausedSession {
                    sessionCard(paused, isPaused: true)
                }

                if !overdueTodos.isEmpty {
                    overdueBanner
                }

                kpiCards

                weeklyChart

                breakdownCharts

                HStack(alignment: .top, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                    ongoingTodosCard
                    recentSessionsCard
                }
            }
            .padding(ProWorkLayout.scaled(24, using: settingsStore))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .proWorkToastNotifications(errorMessage: viewModel.errorMessage)
        .onAppear {
            viewModel.loadData()
        }
        // Previously this view mirrored the shared
        // ProWorkClockTicker into a private @State nowTick on every
        // emission. The copy was redundant — SwiftUI already re-renders
        // when clockTicker.second publishes — and risked drifting if a
        // tick arrived between two reads. All time-derived expressions
        // now read clockTicker.second directly.
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(greetingText)
                    .proWorkTextStyle(.largeTitle)

                Text(formattedDate)
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    /// Previously the hour ranges (5..<12 / 12..<18 / 18..<23)
    /// were inlined into the switch as magic numbers. Extract to named
    /// constants so the cutoff times can be adjusted from one place and
    /// the intent of each band is obvious.
    private static let greetingMorningStart = 5
    private static let greetingAfternoonStart = 12
    private static let greetingEveningStart = 18
    private static let greetingNightStart = 23

    private var greetingText: String {
        // Use Istanbul calendar to keep the greeting consistent with the
        // rest of the app's date math.
        let hour = AppCalendar.istanbul.component(.hour, from: clockTicker.second)
        let key: String
        let fallback: String
        switch hour {
        case Self.greetingMorningStart..<Self.greetingAfternoonStart:
            key = "home.greeting.morning"
            fallback = "Günaydın 👋"
        case Self.greetingAfternoonStart..<Self.greetingEveningStart:
            key = "home.greeting.afternoon"
            fallback = "İyi günler 👋"
        case Self.greetingEveningStart..<Self.greetingNightStart:
            key = "home.greeting.evening"
            fallback = "İyi akşamlar 👋"
        default:
            key = "home.greeting.night"
            fallback = "İyi geceler 👋"
        }
        return settingsStore.localized(key, defaultValue: fallback)
    }

    private var formattedDate: String {
        // K16: cached formatter — body ticks once per second, allocating
        // a new DateFormatter each tick was costing ~1ms on every redraw.
        ProWorkFormatters
            .cachedDateFormatter(
                localeIdentifier: settingsStore.settings.language.localeIdentifier,
                dateStyle: .full
            )
            .string(from: clockTicker.second)
    }

    // MARK: - Active / Paused session card

    private func sessionCard(_ summary: ActiveWorkSessionSummary, isPaused: Bool) -> some View {
        let elapsed: Int = isPaused
            ? summary.elapsedSeconds
            : max(summary.elapsedSeconds, Int(clockTicker.second.timeIntervalSince(summary.startedAt)))

        let bgColor: Color = isPaused ? .orange : .green

        return HStack(alignment: .center, spacing: ProWorkLayout.scaled(16, using: settingsStore)) {
            ZStack {
                Circle()
                    .fill(bgColor.opacity(0.15))
                    .frame(width: ProWorkLayout.scaled(56, using: settingsStore),
                           height: ProWorkLayout.scaled(56, using: settingsStore))
                Image(systemName: isPaused ? "pause.fill" : "play.fill")
                    .proWorkFont(size: 22, weight: .semibold)
                    .foregroundStyle(bgColor)
            }

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(4, using: settingsStore)) {
                Text(isPaused
                     ? settingsStore.localized("home.session.paused", defaultValue: "Duraklatılmış çalışma")
                     : settingsStore.localized("home.session.active", defaultValue: "Aktif çalışma"))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)

                Text(summary.todoTitle)
                    .proWorkTextStyle(.headline)
                    .lineLimit(1)

                Text(summary.statusName)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
                Text(ProWorkFormatters.durationHHmm(elapsed))
                    .proWorkFont(size: 30, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(bgColor)

                HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                    if isPaused {
                        sessionActionButton(
                            title: settingsStore.localized("home.session.resume", defaultValue: "Devam Et"),
                            systemImage: "play.fill",
                            color: .green
                        ) {
                            automationController.resumePausedWork()
                        }
                    } else {
                        sessionActionButton(
                            title: settingsStore.localized("home.session.pause", defaultValue: "Duraklat"),
                            systemImage: "pause.fill",
                            color: .orange
                        ) {
                            automationController.pauseActiveWork()
                        }
                    }

                    sessionActionButton(
                        title: settingsStore.localized("home.session.stop", defaultValue: "Durdur"),
                        systemImage: "stop.fill",
                        color: .red
                    ) {
                        automationController.stopActiveWork()
                    }
                }
            }
        }
        .padding(ProWorkLayout.scaled(18, using: settingsStore))
        .background(bgColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(bgColor.opacity(0.35), lineWidth: 1)
        )
    }

    private func sessionActionButton(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: ProWorkLayout.scaled(5, using: settingsStore)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 11, weight: .semibold)
                Text(title)
                    .proWorkTextStyle(.caption, weight: .semibold)
            }
            .foregroundStyle(color)
            .padding(.horizontal, ProWorkLayout.scaled(10, using: settingsStore))
            .padding(.vertical, ProWorkLayout.scaled(6, using: settingsStore))
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    // MARK: - Overdue banner

    private var overdueBanner: some View {
        Button {
            onNavigate(.todos)
        } label: {
            HStack(spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .proWorkFont(size: 18)
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: ProWorkLayout.scaled(2, using: settingsStore)) {
                    Text(String(format: settingsStore.localized("home.overdue.title", defaultValue: "%d gecikmiş iş var"), overdueTodos.count))
                        .proWorkTextStyle(.callout, weight: .semibold)
                        .foregroundStyle(.primary)

                    Text(settingsStore.localized("home.overdue.subtitle", defaultValue: "Vadesi geçen işleri incelemek için tıklayın."))
                        .proWorkTextStyle(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .proWorkFont(size: 12)
                    .foregroundStyle(.secondary)
        }
        .padding(ProWorkLayout.scaled(14, using: settingsStore))
        .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
            .overlay(
                RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - KPI Cards

    private var kpiCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ProWorkLayout.scaled(14, using: settingsStore)) {
                kpiCard(
                    title: settingsStore.localized("home.kpi.todayDuration", defaultValue: "Bugün Toplam Süre"),
                    value: ProWorkFormatters.durationHHmm(todayTotalSeconds),
                    subtitle: String(format: settingsStore.localized("common.recordCount", defaultValue: "%d kayıt"), todaySessions.count),
                    systemImage: "clock.fill",
                    color: .blue
                )

                kpiCard(
                    title: settingsStore.localized("home.kpi.todayBillable", defaultValue: "Bugün Faturalandırılabilir"),
                    value: ProWorkFormatters.durationHHmm(todayBillableSeconds),
                    subtitle: settingsStore.localized("home.kpi.todayBillable.subtitle", defaultValue: "ücretli süre"),
                    systemImage: "creditcard.fill",
                    color: .green
                )

                kpiCard(
                    title: settingsStore.localized("home.kpi.ongoingTodos", defaultValue: "Devam Eden İş"),
                    value: "\(ongoingTodos.count)",
                    subtitle: settingsStore.localized("home.kpi.ongoingTodos.subtitle", defaultValue: "açık iş"),
                    systemImage: "checklist",
                    color: .purple
                )

                kpiCard(
                    title: settingsStore.localized("home.kpi.overdue", defaultValue: "Gecikmiş İş"),
                    value: "\(overdueTodos.count)",
                    subtitle: settingsStore.localized("home.kpi.overdue.subtitle", defaultValue: "vade geçti"),
                    systemImage: "exclamationmark.triangle.fill",
                    color: overdueTodos.isEmpty ? .secondary : .red
                )

                kpiCard(
                    title: settingsStore.localized("home.kpi.weekDuration", defaultValue: "Bu Hafta"),
                    value: ProWorkFormatters.durationHHmm(weekTotalSeconds),
                    subtitle: settingsStore.localized("home.kpi.weekDuration.subtitle", defaultValue: "toplam süre"),
                    systemImage: "calendar",
                    color: .orange
                )
            }
        }
    }

    private func kpiCard(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 18)
                    .foregroundStyle(color)
                    .frame(width: ProWorkLayout.scaled(24, using: settingsStore))

                Text(title)
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .proWorkFont(size: 26, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(subtitle)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(width: ProWorkLayout.scaled(200, using: settingsStore), alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    // MARK: - Weekly chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: ProWorkLayout.scaled(12, using: settingsStore)) {
            HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                Image(systemName: "chart.bar.fill")
                    .proWorkFont(size: 15)
                    .foregroundStyle(.secondary)
                Text(settingsStore.localized("home.chart.weekTitle", defaultValue: "Son 7 Gün"))
                    .proWorkTextStyle(.headline)
                Spacer()
                Text(ProWorkFormatters.durationHHmm(last7DaysSeconds))
                    .proWorkTextStyle(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Precompute the max once and pass into every bar
            // instead of recomputing inside `weeklyBar(_:)` for each of
            // the 7 bars. The previous form walked the array 7 times
            // per redraw — on each clockTicker tick, that's 49 max()
            // calls per second.
            let weeklyMaxSeconds = max(weeklyData.map { $0.seconds }.max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
                ForEach(weeklyData, id: \.date) { item in
                    weeklyBar(item, maxSeconds: weeklyMaxSeconds)
                }
            }
            .frame(height: ProWorkLayout.scaled(120, using: settingsStore))
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(14, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func weeklyBar(_ item: HomeWeeklyBucket, maxSeconds: Int) -> some View {
        let ratio = CGFloat(item.seconds) / CGFloat(maxSeconds)
        let isToday = AppCalendar.istanbul.isDateInToday(item.date)

        return VStack(spacing: ProWorkLayout.scaled(6, using: settingsStore)) {
            Text(item.seconds > 0 ? ProWorkFormatters.durationHHmm(item.seconds) : "—")
                .proWorkFont(size: 10, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { geo in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isToday ? Color.accentColor : Color.accentColor.opacity(0.55))
                        .frame(height: max(geo.size.height * ratio, item.seconds > 0 ? 4 : 0))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(dayLabel(item.date))
                .proWorkFont(size: 11, weight: isToday ? .semibold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayLabel(_ date: Date) -> String {
        ProWorkFormatters
            .cachedDateFormatter(
                localeIdentifier: settingsStore.settings.language.localeIdentifier,
                dateFormat: "EEE"
            )
            .string(from: date)
    }

    // MARK: - Ongoing todos

    /// The ViewThatFits branches used to repeat each
    /// `ProWorkDonutBreakdownCard` configuration verbatim. SwiftUI
    /// would build both branches to pick the wider one, so the second
    /// (vertical) copy paid the same construction cost as the first
    /// (horizontal) copy — and every label/row change had to land in
    /// two places. Extract the card builders into a private `@ViewBuilder`
    /// helper so both layouts compose them once.
    @ViewBuilder
    private var breakdownCards: some View {
        ProWorkDonutBreakdownCard(
            title: settingsStore.localized("home.pie.categoryTitle", defaultValue: "Bu Ay Kategori Dağılımı"),
            systemImage: "tag.fill",
            rows: categoryBreakdownRows,
            emptyMessage: settingsStore.localized("home.pie.empty.category", defaultValue: "Bu ay kategori bazlı süre verisi yok.")
        )

        ProWorkDonutBreakdownCard(
            title: settingsStore.localized("home.pie.customerTitle", defaultValue: "Bu Ay Müşteri Dağılımı"),
            systemImage: "person.2.fill",
            rows: customerBreakdownRows,
            emptyMessage: settingsStore.localized("home.pie.empty.customer", defaultValue: "Bu ay müşteri bazlı süre verisi yok.")
        )
    }

    private var breakdownCharts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                breakdownCards
            }

            VStack(alignment: .leading, spacing: ProWorkLayout.scaled(20, using: settingsStore)) {
                breakdownCards
            }
        }
    }

    private var ongoingTodosCard: some View {
        listCard(
            title: settingsStore.localized("home.ongoing.title", defaultValue: "Devam Eden İşler"),
            systemImage: "checklist",
            actionTitle: settingsStore.localized("home.viewAll", defaultValue: "Tümünü gör"),
            action: { onNavigate(.todos) }
        ) {
            if ongoingTodosTopFive.isEmpty {
                emptyRow(text: settingsStore.localized("home.ongoing.empty", defaultValue: "Açık iş bulunmuyor."))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ongoingTodosTopFive.enumerated()), id: \.element.id) { index, todo in
                        if index > 0 { Divider() }
                        ongoingTodoRow(todo)
                    }
                }
            }
        }
    }

    private func ongoingTodoRow(_ todo: TodoListItem) -> some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Circle()
                .fill(ProWorkLabels.priorityColor(todo.priority))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .proWorkTextStyle(.callout)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let customer = todo.customerName {
                        Text(customer)
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let project = todo.projectName {
                        Text("·").foregroundStyle(.secondary)
                        Text(project)
                            .proWorkTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            if let due = todo.dueDate {
                let isOverdue = due < AppCalendar.istanbul.startOfDay(for: clockTicker.second)
                Text(formatShortDate(due))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(isOverdue ? Color.red : .secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, ProWorkLayout.scaled(14, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(10, using: settingsStore))
    }

    // Priority color mapping consolidated in
    // ProWorkLabels.priorityColor; the local copy is removed.

    // MARK: - Recent sessions

    private var recentSessionsCard: some View {
        listCard(
            title: settingsStore.localized("home.recent.title", defaultValue: "Son Çalışma Kayıtları"),
            systemImage: "clock.arrow.circlepath",
            actionTitle: settingsStore.localized("home.viewAll", defaultValue: "Tümünü gör"),
            action: { onNavigate(.workSessions) }
        ) {
            if recentSessionsTopFive.isEmpty {
                emptyRow(text: settingsStore.localized("home.recent.empty", defaultValue: "Henüz kayıt yok."))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentSessionsTopFive.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { Divider() }
                        recentSessionRow(session)
                    }
                }
            }
        }
    }

    private func recentSessionRow(_ session: WorkSessionListItem) -> some View {
        HStack(spacing: ProWorkLayout.scaled(10, using: settingsStore)) {
            Image(systemName: session.isManual ? "hand.point.up.left.fill" : "play.fill")
                .proWorkFont(size: 12)
                .foregroundStyle(session.isManual ? Color.orange : Color.green)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.todoTitle)
                    .proWorkTextStyle(.callout)
                    .lineLimit(1)

                Text(formatRelativeStart(session.startedAt))
                    .proWorkTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(ProWorkFormatters.durationHHmm(session.durationSeconds ?? 0))
                .proWorkTextStyle(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ProWorkLayout.scaled(14, using: settingsStore))
        .padding(.vertical, ProWorkLayout.scaled(10, using: settingsStore))
    }

    // MARK: - List card shell

    private func listCard<Content: View>(
        title: String,
        systemImage: String,
        actionTitle: String?,
        action: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ProWorkLayout.scaled(8, using: settingsStore)) {
                Image(systemName: systemImage)
                    .proWorkFont(size: 14)
                    .foregroundStyle(.secondary)
                Text(title)
                    .proWorkTextStyle(.headline)

                Spacer()

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: 3) {
                            Text(actionTitle)
                                .proWorkTextStyle(.caption, weight: .medium)
                            Image(systemName: "chevron.right")
                                .proWorkFont(size: 10, weight: .semibold)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(ProWorkLayout.scaled(14, using: settingsStore))
            .background(.quaternary.opacity(0.35))

            Divider()

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore)))
        .overlay(
            RoundedRectangle(cornerRadius: ProWorkLayout.scaled(12, using: settingsStore))
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func emptyRow(text: String) -> some View {
        HStack {
            Text(text)
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(ProWorkLayout.scaled(16, using: settingsStore))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derived data

    private var todaySessions: [WorkSessionListItem] {
        let startOfDay = AppCalendar.istanbul.startOfDay(for: clockTicker.second)
        return viewModel.sessions.filter { $0.endedAt != nil && $0.startedAt >= startOfDay }
    }

    private var todayTotalSeconds: Int {
        todaySessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    private var todayBillableSeconds: Int {
        todaySessions.filter { $0.statusStartsTimer }.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    private var weekStart: Date {
        AppCalendar.istanbul.dateInterval(of: .weekOfYear, for: clockTicker.second)?.start ?? clockTicker.second
    }

    private var weekTotalSeconds: Int {
        viewModel.sessions
            .filter { $0.endedAt != nil && $0.startedAt >= weekStart }
            .reduce(0) { $0 + ($1.durationSeconds ?? 0) }
    }

    private var ongoingTodos: [TodoListItem] {
        viewModel.todos.filter { !$0.statusMarksCompleted && !$0.statusMarksCancelled }
    }

    private var ongoingTodosTopFive: [TodoListItem] {
        ongoingTodos
            .sorted { lhs, rhs in
                let lhsDue = lhs.dueDate ?? Date.distantFuture
                let rhsDue = rhs.dueDate ?? Date.distantFuture
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(5)
            .map { $0 }
    }

    private var overdueTodos: [TodoListItem] {
        let startOfToday = AppCalendar.istanbul.startOfDay(for: clockTicker.second)
        return ongoingTodos.filter { todo in
            guard let due = todo.dueDate else { return false }
            return due < startOfToday
        }
    }

    private var recentSessionsTopFive: [WorkSessionListItem] {
        viewModel.sessions
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(5)
            .map { $0 }
    }

    /// Previously this 7-day aggregation re-ran on every
    /// clockTicker.second emission (≈60×/min), filtering all sessions for
    /// each of the 7 buckets — O(7·N) work per tick. The output only
    /// changes when sessions reload or the day rolls over, so route
    /// through HomeViewModel's cached property which invalidates on
    /// session changes; the day-rollover invalidation lives in the
    /// view model's halfMinute observer.
    private var weeklyData: [HomeWeeklyBucket] {
        viewModel.weeklyData(reference: clockTicker.halfMinute)
    }

    private var last7DaysSeconds: Int {
        weeklyData.reduce(0) { $0 + $1.seconds }
    }

    /// Routed through the view model's cached lookup so the
    /// per-second tick doesn't rebuild a fresh Dictionary.
    private var todoLookup: [String: TodoListItem] {
        viewModel.todoLookup()
    }

    /// Routed through the VM-cached month bucket. Using
    /// `clockTicker.halfMinute` (instead of `second`) is sufficient
    /// because the only state that affects month membership is the
    /// month-end rollover, which the half-minute granularity catches.
    private var currentMonthSessions: [WorkSessionListItem] {
        viewModel.currentMonthSessions(reference: clockTicker.halfMinute)
    }

    private var categoryBreakdownRows: [DonutBreakdownRow] {
        SessionBreakdownBuilder.categoryRows(
            sessions: currentMonthSessions,
            todoLookup: todoLookup,
            unknownTitle: settingsStore.localized("home.pie.unknownCategory", defaultValue: "Kategorisiz"),
            otherTitle: settingsStore.localized("home.pie.other", defaultValue: "Diğer")
        )
    }

    private var customerBreakdownRows: [DonutBreakdownRow] {
        SessionBreakdownBuilder.customerRows(
            sessions: currentMonthSessions,
            noCustomerTitle: settingsStore.localized("home.pie.noCustomer", defaultValue: "Müşterisiz"),
            otherTitle: settingsStore.localized("home.pie.other", defaultValue: "Diğer")
        )
    }

    // MARK: - Date formatting helpers

    private func formatShortDate(_ date: Date) -> String {
        ProWorkFormatters
            .cachedDateFormatter(
                localeIdentifier: settingsStore.settings.language.localeIdentifier,
                dateFormat: "d MMM"
            )
            .string(from: date)
    }

    private func formatRelativeStart(_ date: Date) -> String {
        let localeId = settingsStore.settings.language.localeIdentifier
        let calendar = AppCalendar.istanbul
        if calendar.isDateInToday(date) {
            let formatter = ProWorkFormatters.cachedDateFormatter(
                localeIdentifier: localeId,
                dateStyle: .none,
                timeStyle: .short
            )
            return String(format: settingsStore.localized("home.recent.today", defaultValue: "Bugün %@"), formatter.string(from: date))
        }
        if calendar.isDateInYesterday(date) {
            let formatter = ProWorkFormatters.cachedDateFormatter(
                localeIdentifier: localeId,
                dateStyle: .none,
                timeStyle: .short
            )
            return String(format: settingsStore.localized("home.recent.yesterday", defaultValue: "Dün %@"), formatter.string(from: date))
        }
        return ProWorkFormatters
            .cachedDateFormatter(
                localeIdentifier: localeId,
                dateStyle: .short,
                timeStyle: .short
            )
            .string(from: date)
    }

}
